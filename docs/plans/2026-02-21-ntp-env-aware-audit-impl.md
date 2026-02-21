# NTP Environment-Aware + ntp_audit Role Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the `ntp` role adapt chrony config to the detected VM environment (Hyper-V, KVM,
VMware, VirtualBox, bare metal), disable all competing time sync daemons, and introduce a new
init-system-agnostic `ntp_audit` role for runtime conflict detection and logging.

**Architecture:** The `ntp` role reads `ansible_facts['virtualization_type']` and injects the
appropriate `refclock PHC` directive and `makestep`/`rtcsync` values into `chrony.conf.j2`. The
`ntp_audit` role deploys a shell script that runs on a schedule (systemd timer or cron), writes
structured JSON to `/var/log/ntp-audit/audit.log`, and pre-deploys Grafana Alloy + Loki ruler
configs for zero-effort monitoring stack integration.

**Tech Stack:** Ansible, chrony, systemd timer / cron, `logger(1)`, Grafana Alloy (config only),
Loki ruler rules (config only), Molecule (verify driver, localhost).

**Design doc:** `docs/plans/2026-02-21-ntp-env-aware-audit-design.md`

---

## Context: Existing ntp role structure

```
ansible/roles/ntp/
  defaults/main.yml        # ntp_enabled, ntp_servers, ntp_makestep_*, ntp_rtcsync, ...
  vars/main.yml            # _ntp_service, _ntp_package, _ntp_user mappings
  tasks/
    main.yml               # validate → install → disable_systemd → dirs → config → start → verify
    disable_systemd.yml    # stop+disable systemd-timesyncd (with_first_found pattern)
    validate.yml
    verify.yml
  templates/
    chrony.conf.j2         # server/pool blocks + driftfile + makestep + rtcsync + logdir
  handlers/main.yml        # "restart ntp" listen handler → chronyd restart
  molecule/default/
    molecule.yml           # driver: default (local), verifier: ansible
    converge.yml           # runs ntp role on localhost (Arch Linux only)
    verify.yml             # 15+ assertions: chrony running, synced, NTS active, dirs exist
```

Key patterns to follow:
- `with_first_found` + `skip: true` for init-system-specific files (see `disable_systemd.yml`)
- `failed_when: "'could not be found' not in ..."` for idempotent service operations
- `common` role for `report_phase.yml` / `report_render.yml` / `check_internet.yml`
- All verify tasks are in `molecule/default/verify.yml`, not in role `tasks/verify.yml`

---

## Part A: ntp role changes

---

### Task A1: Add new variables to defaults/main.yml

**Files:**
- Modify: `ansible/roles/ntp/defaults/main.yml`

**Step 1: Append new variables**

Add after the existing `ntp_ntsdumpdir` block:

```yaml
# === Environment detection ===
# When true, reads ansible_facts['virtualization_type'] and adapts chrony config:
#   refclock PHC, makestep, rtcsync per hypervisor
# Set false to use ntp_refclocks manually.
ntp_auto_detect: true

# Manual refclock directives (list of raw chrony refclock strings).
# Populated automatically from detected environment when ntp_auto_detect: true.
# Override to force specific refclocks regardless of detected environment.
# Example: ["refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0 stratum 2"]
ntp_refclocks: []

# Stop and disable ntpd and openntpd if found (in addition to systemd-timesyncd).
ntp_disable_competitors: true

# On VMware guests: run `vmware-toolbox-cmd timesync disable` to stop periodic sync.
# One-off sync events (vMotion, snapshot restore) are left enabled — they are safe.
# Has no effect on non-VMware systems.
ntp_vmware_disable_periodic_sync: true
```

**Step 2: Verify syntax**

Run on remote VM:
```bash
cd /home/textyre/.local/share/chezmoi && \
  python3 -c "import yaml; yaml.safe_load(open('ansible/roles/ntp/defaults/main.yml'))" && \
  echo "YAML valid"
```
Expected: `YAML valid`

**Step 3: Commit**

```bash
git add ansible/roles/ntp/defaults/main.yml
git commit -m "feat(ntp): add auto-detect, refclocks, competitor-disable variables"
```

---

### Task A2: Add environment mapping to vars/environments.yml

**Files:**
- Create: `ansible/roles/ntp/vars/environments.yml`

**Step 1: Create the file**

```yaml
---
# === NTP environment mappings ===
# Keyed by ansible_facts['virtualization_type'].
# Values are merged into chrony.conf template variables.
#
# refclock: list of raw chrony refclock directives (empty = no PHC source)
# rtcsync:  bool — sync hardware RTC to system clock
# makestep_threshold: float — step if offset exceeds this (seconds)
# makestep_limit:     int   — only step in first N updates; -1 = unlimited
#
# References:
#   Hyper-V:  https://learn.microsoft.com/azure/virtual-machines/linux/time-sync
#   KVM:      https://lkml.iu.edu/hypermail/linux/kernel/1701.3/00549.html
#   VMware:   https://knowledge.broadcom.com/external/article/310053
#   VirtualBox: https://www.virtualbox.org/manual/ch09.html

_ntp_env_defaults:
  refclocks: []
  rtcsync: true
  makestep_threshold: 1.0
  makestep_limit: 3

_ntp_env_map:
  # Hyper-V: hv_utils exposes /dev/ptp_hyperv. chrony uses it as stratum 2.
  hyperv:
    refclocks:
      - "refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0 stratum 2"
    rtcsync: false        # RTC is managed by the Hyper-V host
    makestep_threshold: 1.0
    makestep_limit: -1    # unlimited: tolerate jumps after VM resume

  # KVM: ptp_kvm module exposes /dev/ptp0 (or /dev/ptp_kvm symlink).
  # Module must be loaded — handled by load_ptp_kvm.yml task.
  kvm:
    refclocks:
      - "refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0 stratum 2"
    rtcsync: false
    makestep_threshold: 1.0
    makestep_limit: -1

  # VMware: ptp_vmw (Linux 5.7+) exposes /dev/ptp0 when Precision Clock device
  # is added in vSphere 7.0 U2+ with VM hardware version 17+.
  # Presence of /dev/ptp0 is checked at task runtime; refclock only added if found.
  vmware:
    refclocks: []         # populated conditionally by detect_environment.yml
    rtcsync: false
    makestep_threshold: 1.0
    makestep_limit: -1

  # VirtualBox: no PTP device. Cannot integrate with VBoxService from guest.
  # makestep -1 tolerates jumps from VBoxService on resume/snapshot.
  virtualbox:
    refclocks: []
    rtcsync: false
    makestep_threshold: 1.0
    makestep_limit: -1

  # Bare metal and unknown: use role defaults unchanged.
  none:
    refclocks: []
    rtcsync: "{{ ntp_rtcsync }}"
    makestep_threshold: "{{ ntp_makestep_threshold }}"
    makestep_limit: "{{ ntp_makestep_limit }}"
```

**Step 2: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/ntp/vars/environments.yml'))" && echo "YAML valid"
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp/vars/environments.yml
git commit -m "feat(ntp): add per-hypervisor environment config mappings"
```

---

### Task A3: Create detect_environment.yml

**Files:**
- Create: `ansible/roles/ntp/tasks/detect_environment.yml`

**Step 1: Create the task file**

```yaml
---
# === NTP environment detection ===
# Reads ansible_facts['virtualization_type'] and sets:
#   _ntp_virt_type      — normalized virt type (hyperv/kvm/vmware/virtualbox/none)
#   _ntp_env            — merged config dict from _ntp_env_map
#   _ntp_active_refclocks — final list of refclock strings for chrony.conf

- name: "NTP env: Determine virtualization type"
  ansible.builtin.set_fact:
    _ntp_virt_type: >-
      {{ ansible_facts['virtualization_type'] | default('none')
         if (ansible_facts['virtualization_role'] | default('') == 'guest')
         else 'none' }}
  tags: ['ntp']

- name: "NTP env: Load environment config"
  ansible.builtin.set_fact:
    _ntp_env: >-
      {{ _ntp_env_map[_ntp_virt_type] | default(_ntp_env_defaults)
         | combine(_ntp_env_defaults, recursive=false, list_merge='replace') }}
  tags: ['ntp']

# VMware: check if /dev/ptp0 actually exists before adding refclock.
# ptp_vmw requires vSphere 7.0 U2+ and Precision Clock device added to VM.
- name: "NTP env: Check VMware PTP device presence"
  ansible.builtin.stat:
    path: /dev/ptp0
  register: _ntp_vmware_ptp_stat
  when: _ntp_virt_type == 'vmware'
  tags: ['ntp']

- name: "NTP env: Set VMware refclock if PTP device present"
  ansible.builtin.set_fact:
    _ntp_env: >-
      {{ _ntp_env | combine({
           'refclocks': ['refclock PHC /dev/ptp0 poll 0 delay 0.0004 stratum 1']
         }) }}
  when:
    - _ntp_virt_type == 'vmware'
    - _ntp_vmware_ptp_stat.stat.exists | default(false)
  tags: ['ntp']

# Final refclock list: user-supplied ntp_refclocks takes priority over auto-detected.
- name: "NTP env: Resolve final refclock list"
  ansible.builtin.set_fact:
    _ntp_active_refclocks: >-
      {{ ntp_refclocks if (ntp_refclocks | length > 0)
         else _ntp_env.refclocks | default([]) }}
  tags: ['ntp']

- name: "NTP env: Report detected environment"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_ntp_phases"
    _rpt_phase: "Detect environment"
    _rpt_detail: >-
      virt={{ _ntp_virt_type }}
      refclocks={{ _ntp_active_refclocks | length }}
      rtcsync={{ _ntp_env.rtcsync }}
  tags: ['ntp']
```

**Step 2: Lint**

```bash
ansible-lint ansible/roles/ntp/tasks/detect_environment.yml
```
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/roles/ntp/tasks/detect_environment.yml
git commit -m "feat(ntp): add environment detection task (virtualization_type → chrony config)"
```

---

### Task A4: Create disable_ntpd.yml and disable_openntpd.yml

**Files:**
- Create: `ansible/roles/ntp/tasks/disable_ntpd.yml`
- Create: `ansible/roles/ntp/tasks/disable_openntpd.yml`

**Step 1: Create disable_ntpd.yml**

Pattern mirrors existing `disable_systemd.yml`:

```yaml
---
# Disable ntpd (classic NTP daemon) — conflicts with chrony

- name: Disable ntpd (conflicts with chrony)
  ansible.builtin.service:
    name: ntpd
    enabled: false
    state: stopped
  register: _ntp_ntpd_disable
  failed_when:
    - _ntp_ntpd_disable is failed
    - >-
      'could not be found' not in (_ntp_ntpd_disable.msg | default(''))
      and 'No such file' not in (_ntp_ntpd_disable.msg | default(''))
  tags: ['ntp']
```

**Step 2: Create disable_openntpd.yml**

```yaml
---
# Disable openntpd — conflicts with chrony

- name: Disable openntpd (conflicts with chrony)
  ansible.builtin.service:
    name: openntpd
    enabled: false
    state: stopped
  register: _ntp_openntpd_disable
  failed_when:
    - _ntp_openntpd_disable is failed
    - >-
      'could not be found' not in (_ntp_openntpd_disable.msg | default(''))
      and 'No such file' not in (_ntp_openntpd_disable.msg | default(''))
  tags: ['ntp']
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp/tasks/disable_ntpd.yml ansible/roles/ntp/tasks/disable_openntpd.yml
git commit -m "feat(ntp): disable ntpd and openntpd if present (competitor cleanup)"
```

---

### Task A5: Create load_ptp_kvm.yml

**Files:**
- Create: `ansible/roles/ntp/tasks/load_ptp_kvm.yml`

**Step 1: Create the file**

```yaml
---
# Load ptp_kvm kernel module for KVM guests (Linux 4.11+, x86).
# Exposes /dev/ptp0 (or /dev/ptp_kvm) for chrony refclock PHC.
# Reference: https://lkml.iu.edu/hypermail/linux/kernel/1701.3/00549.html

- name: "KVM: Load ptp_kvm module immediately"
  community.general.modprobe:
    name: ptp_kvm
    state: present
  register: _ntp_ptp_kvm_load
  failed_when:
    - _ntp_ptp_kvm_load is failed
    - "'not found' not in (_ntp_ptp_kvm_load.msg | default(''))"
  tags: ['ntp']

- name: "KVM: Persist ptp_kvm module across reboots"
  ansible.builtin.copy:
    dest: /etc/modules-load.d/ptp_kvm.conf
    content: "ptp_kvm\n"
    owner: root
    group: root
    mode: "0644"
  tags: ['ntp']

- name: "KVM: Verify /dev/ptp0 is present after module load"
  ansible.builtin.stat:
    path: /dev/ptp0
  register: _ntp_ptp0_stat
  tags: ['ntp']

- name: "KVM: Warn if /dev/ptp0 not found after loading ptp_kvm"
  ansible.builtin.debug:
    msg: >-
      WARNING: ptp_kvm module loaded but /dev/ptp0 not found.
      Kernel may be < 4.11 or module not supported on this CPU.
      chrony will use NTS servers only (no local PHC reference).
  when: not (_ntp_ptp0_stat.stat.exists | default(false))
  tags: ['ntp']
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp/tasks/load_ptp_kvm.yml
git commit -m "feat(ntp): add ptp_kvm module loading for KVM guests"
```

---

### Task A6: Create vmware_disable_timesync.yml

**Files:**
- Create: `ansible/roles/ntp/tasks/vmware_disable_timesync.yml`

**Step 1: Create the file**

```yaml
---
# Disable VMware Tools periodic time synchronization.
# Periodic sync (every 60s) conflicts with chrony — disable it.
# One-off sync on vMotion/snapshot restore is left enabled (safe with chrony).
# Reference: https://knowledge.broadcom.com/external/article/310053

- name: "VMware: Check if vmware-toolbox-cmd is available"
  ansible.builtin.command:
    cmd: which vmware-toolbox-cmd
  register: _ntp_vmware_toolbox_check
  changed_when: false
  failed_when: false
  tags: ['ntp']

- name: "VMware: Check current timesync status"
  ansible.builtin.command:
    cmd: vmware-toolbox-cmd timesync status
  register: _ntp_vmware_timesync_status
  changed_when: false
  failed_when: false
  when: _ntp_vmware_toolbox_check.rc == 0
  tags: ['ntp']

- name: "VMware: Disable periodic timesync"
  ansible.builtin.command:
    cmd: vmware-toolbox-cmd timesync disable
  when:
    - _ntp_vmware_toolbox_check.rc == 0
    - _ntp_vmware_timesync_status.stdout | default('') != 'Disabled'
  changed_when: true
  tags: ['ntp']
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp/tasks/vmware_disable_timesync.yml
git commit -m "feat(ntp): disable VMware Tools periodic time sync"
```

---

### Task A7: Update chrony.conf.j2 template

**Files:**
- Modify: `ansible/roles/ntp/templates/chrony.conf.j2`

**Step 1: Replace the template**

```jinja2
# Managed by Ansible — do not edit manually
# Role: ntp | Template: chrony.conf.j2
# Environment: {{ _ntp_virt_type | default('unknown') }}

{% for server in ntp_servers %}
server {{ server.host }}{% if server.iburst | default(true) %} iburst{% endif %}{% if server.nts | default(false) %} nts{% endif %}

{% endfor %}
{% for pool in ntp_pools %}
pool {{ pool.host }}{% if pool.iburst | default(true) %} iburst{% endif %}{% if pool.maxsources is defined %} maxsources {{ pool.maxsources }}{% endif %}

{% endfor %}
{% if _ntp_active_refclocks | default([]) | length > 0 %}
# PTP hardware clock reference ({{ _ntp_virt_type | default('auto') }})
{% for refclock in _ntp_active_refclocks %}
{{ refclock }}
{% endfor %}

{% endif %}
# Clock stability
driftfile {{ ntp_driftfile }}
{% if ntp_dumpdir %}
dumpdir {{ ntp_dumpdir }}
{% endif %}
{% if ntp_ntsdumpdir %}
ntsdumpdir {{ ntp_ntsdumpdir }}
{% endif %}
makestep {{ _ntp_env.makestep_threshold | default(ntp_makestep_threshold) }} {{ _ntp_env.makestep_limit | default(ntp_makestep_limit) }}
minsources {{ ntp_minsources }}

{% if _ntp_env.rtcsync | default(ntp_rtcsync) %}
# Sync hardware RTC to system clock
rtcsync
{% endif %}

# Leap seconds from system timezone database
leapsectz right/UTC

# Logging
logdir {{ ntp_logdir }}
logchange {{ ntp_logchange }}
{% if ntp_log_tracking %}
log measurements statistics tracking
{% endif %}
{% if ntp_allow | length > 0 %}
# NTP server mode — allow these networks to query this host
{% for cidr in ntp_allow %}
allow {{ cidr }}
{% endfor %}
{% endif %}
```

**Step 2: Run molecule to verify template renders correctly**

Run on remote VM:
```bash
task test-ntp
```
Expected: all molecule verify assertions pass (chrony running, synced, NTS active)

**Step 3: Commit**

```bash
git add ansible/roles/ntp/templates/chrony.conf.j2
git commit -m "feat(ntp): update chrony.conf.j2 — conditional refclock, env-aware makestep/rtcsync"
```

---

### Task A8: Wire new tasks into main.yml

**Files:**
- Modify: `ansible/roles/ntp/tasks/main.yml`

**Step 1: Add environment detection, module loading, competitor disable, VMware timesync**

Insert the new task blocks in correct order. The full updated `main.yml`:

```yaml
---
# === NTP — синхронизация времени ===
# chrony как универсальный NTP-демон (все дистро, все init-системы)
# validate → Env detect → Конкуренты → Установка → Конфигурация → Директории → Запуск → Проверка → Логирование

- name: NTP role
  when: ntp_enabled | bool
  tags: ['ntp']
  block:

    # ======================================================================
    # ---- Валидация ----
    # ======================================================================

    - name: Validate NTP configuration
      ansible.builtin.include_tasks: validate.yml
      tags: ['ntp']

    # ======================================================================
    # ---- Определение среды ----
    # ======================================================================

    - name: Include environment variable mappings
      ansible.builtin.include_vars: environments.yml
      tags: ['ntp']

    - name: Detect virtualization environment
      ansible.builtin.include_tasks: detect_environment.yml
      when: ntp_auto_detect | bool
      tags: ['ntp']

    # Set defaults when auto-detect is disabled
    - name: Set default environment facts (auto-detect disabled)
      ansible.builtin.set_fact:
        _ntp_virt_type: "none"
        _ntp_env: "{{ _ntp_env_defaults }}"
        _ntp_active_refclocks: "{{ ntp_refclocks }}"
      when: not (ntp_auto_detect | bool)
      tags: ['ntp']

    # ======================================================================
    # ---- KVM: загрузка модуля ptp_kvm ----
    # ======================================================================

    - name: Load ptp_kvm module (KVM only)
      ansible.builtin.include_tasks: load_ptp_kvm.yml
      when: _ntp_virt_type == 'kvm'
      tags: ['ntp']

    # ======================================================================
    # ---- Отключение конфликтующих демонов ----
    # ======================================================================

    - name: Disable competing time sync daemons (init-specific)
      ansible.builtin.include_tasks: "{{ item }}"
      with_first_found:
        - files:
            - "disable_{{ ansible_facts['service_mgr'] }}.yml"
          skip: true
      tags: ['ntp']

    - name: Disable ntpd (all systems)
      ansible.builtin.include_tasks: disable_ntpd.yml
      when: ntp_disable_competitors | bool
      tags: ['ntp']

    - name: Disable openntpd (all systems)
      ansible.builtin.include_tasks: disable_openntpd.yml
      when: ntp_disable_competitors | bool
      tags: ['ntp']

    - name: Disable VMware periodic time sync
      ansible.builtin.include_tasks: vmware_disable_timesync.yml
      when:
        - _ntp_virt_type == 'vmware'
        - ntp_vmware_disable_periodic_sync | bool
      tags: ['ntp']

    # ======================================================================
    # ---- Установка ----
    # ======================================================================

    - name: Install NTP daemon (chrony)
      ansible.builtin.package:
        name: "{{ _ntp_package[ansible_facts['os_family']] | default('chrony') }}"
        state: present
      tags: ['ntp']

    # ======================================================================
    # ---- Директории ----
    # ======================================================================

    - name: Ensure chrony directories exist
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: directory
        owner: "{{ _ntp_user[ansible_facts['os_family']] | default('chrony') }}"
        group: "{{ _ntp_user[ansible_facts['os_family']] | default('chrony') }}"
        mode: "{{ item.mode }}"
      loop:
        - { path: "{{ ntp_logdir }}",     mode: "0755" }
        - { path: "{{ ntp_dumpdir }}",    mode: "0750" }
        - { path: "{{ ntp_ntsdumpdir }}", mode: "0700" }
      tags: ['ntp']

    # ======================================================================
    # ---- Конфигурация ----
    # ======================================================================

    - name: Deploy chrony configuration
      ansible.builtin.template:
        src: chrony.conf.j2
        dest: /etc/chrony.conf
        owner: root
        group: root
        mode: "0644"
      notify: restart ntp
      tags: ['ntp']

    # ======================================================================
    # ---- Запуск chrony ----
    # ======================================================================

    - name: Enable and start chronyd
      ansible.builtin.service:
        name: "{{ _ntp_service[ansible_facts['service_mgr']] | default('chronyd') }}"
        enabled: true
        state: started
      tags: ['ntp', 'ntp:state']

    # ======================================================================
    # ---- Проверка ----
    # ======================================================================

    - name: Verify NTP
      ansible.builtin.include_tasks: verify.yml
      tags: ['ntp']

    # ======================================================================
    # ---- Логирование ----
    # ======================================================================

    - name: "Report: NTP"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_ntp_phases"
        _rpt_phase: "Configure NTP"
        _rpt_detail: >-
          chrony ({{ _ntp_service[ansible_facts['service_mgr']] | default('chronyd') }})
          env={{ _ntp_virt_type | default('unknown') }}
          refclocks={{ _ntp_active_refclocks | default([]) | length }}
      tags: ['ntp', 'report']

    - name: "ntp — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        _rpt_fact: "_ntp_phases"
        _rpt_title: "ntp"
      tags: ['ntp', 'report']
```

**Step 2: Run syntax check on remote VM**

```bash
ansible-playbook ansible/playbooks/workstation.yml --tags ntp --syntax-check
```
Expected: no errors

**Step 3: Run molecule**

```bash
task test-ntp
```
Expected: all assertions pass

**Step 4: Commit**

```bash
git add ansible/roles/ntp/tasks/main.yml
git commit -m "feat(ntp): wire environment detection, ptp_kvm, competitor disable into main.yml"
```

---

### Task A9: Update molecule verify.yml for new behavior

**Files:**
- Modify: `ansible/roles/ntp/molecule/default/verify.yml`

**Step 1: Add assertions after existing tests**

Append at end of `verify.yml` (before the final "Show result" task):

```yaml
    # ---- environment detection ----

    - name: Read deployed chrony.conf
      ansible.builtin.slurp:
        src: /etc/chrony.conf
      register: _verify_conf_raw

    - name: Decode chrony.conf
      ansible.builtin.set_fact:
        _verify_conf: "{{ _verify_conf_raw.content | b64decode }}"

    - name: Assert environment comment present in chrony.conf
      ansible.builtin.assert:
        that:
          - "'# Environment:' in _verify_conf"
        fail_msg: "chrony.conf missing environment detection comment — template not updated"

    # ---- competitor services ----

    - name: Check systemd-timesyncd is not active (systemd only)
      ansible.builtin.service_facts:
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert systemd-timesyncd is stopped/disabled
      ansible.builtin.assert:
        that: >-
          ansible_facts.services['systemd-timesyncd.service'].state | default('') != 'running'
        fail_msg: "systemd-timesyncd is still running — should be disabled by ntp role"
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - "'systemd-timesyncd.service' in ansible_facts.services"

    # ---- KVM refclock (only on KVM guests) ----

    - name: Check ptp_kvm module loaded (KVM only)
      ansible.builtin.command:
        cmd: lsmod
      register: _verify_lsmod
      changed_when: false
      when: ansible_facts['virtualization_type'] | default('') == 'kvm'

    - name: Assert ptp_kvm loaded on KVM
      ansible.builtin.assert:
        that:
          - "'ptp_kvm' in _verify_lsmod.stdout"
        fail_msg: "ptp_kvm module not loaded on KVM guest"
      when: ansible_facts['virtualization_type'] | default('') == 'kvm'

    - name: Assert refclock present in chrony.conf on KVM
      ansible.builtin.assert:
        that:
          - "'refclock PHC' in _verify_conf"
        fail_msg: "refclock PHC missing from chrony.conf on KVM guest"
      when: ansible_facts['virtualization_type'] | default('') == 'kvm'

    - name: Assert refclock present in chrony.conf on Hyper-V
      ansible.builtin.assert:
        that:
          - "'refclock PHC /dev/ptp_hyperv' in _verify_conf"
        fail_msg: "refclock PHC /dev/ptp_hyperv missing from chrony.conf on Hyper-V guest"
      when: ansible_facts['virtualization_type'] | default('') == 'hyperv'
```

**Step 2: Run molecule**

```bash
task test-ntp
```
Expected: all assertions pass including new ones

**Step 3: Commit**

```bash
git add ansible/roles/ntp/molecule/default/verify.yml
git commit -m "test(ntp): add environment detection and competitor assertions to molecule verify"
```

---

## Part B: ntp_audit role (new)

---

### Task B1: Scaffold ntp_audit role

**Step 1: Use the ansible-role-creator skill**

Run `/ansible-role-creator` with prompt:
> Scaffold role `ntp_audit` at `ansible/roles/ntp_audit/`. No handlers needed.
> meta: depends on nothing. Tags: `['ntp_audit']`.
> Do NOT add to workstation.yml yet — Task B6 handles that.

Or manually create structure:

```bash
mkdir -p ansible/roles/ntp_audit/{defaults,tasks,templates,meta,molecule/default}
```

**Step 2: Create meta/main.yml**

```yaml
---
galaxy_info:
  role_name: ntp_audit
  description: "Runtime NTP health audit — init-system agnostic, Alloy/Loki ready"
  min_ansible_version: "2.14"

dependencies: []
```

**Step 3: Create defaults/main.yml**

```yaml
---
# === ntp_audit — runtime NTP health audit ===

# Enable/disable the audit role entirely
ntp_audit_enabled: true

# Audit schedule interval.
# systemd systems: OnCalendar value (e.g. "*:0/5" = every 5 min)
# non-systemd:     cron schedule (e.g. "*/5 * * * *")
ntp_audit_interval_systemd: "*:0/5"
ntp_audit_interval_cron: "*/5 * * * *"

# Where audit script writes structured JSON output
ntp_audit_log_dir: "/var/log/ntp-audit"
ntp_audit_log_file: "/var/log/ntp-audit/audit.log"

# Competing services to check (add/remove as needed)
ntp_audit_competitor_services:
  - systemd-timesyncd
  - ntpd
  - openntpd
  - vmtoolsd

# PHC devices to check for presence
ntp_audit_phc_devices:
  - /dev/ptp_hyperv
  - /dev/ptp0

# Kernel modules to check (empty = skip)
ntp_audit_kernel_modules:
  - ptp_kvm

# Grafana Alloy config fragment destination.
# Set to "" to skip Alloy config deployment.
ntp_audit_alloy_config_dir: "/etc/alloy/conf.d"

# Loki ruler rules destination.
# Set to "" to skip Loki rules deployment.
ntp_audit_loki_rules_dir: "/etc/loki/rules/fake"

# Alert thresholds
ntp_audit_alert_offset_threshold: "0.1"   # seconds — alert if |offset| > this
ntp_audit_alert_stratum_max: "4"          # alert if stratum > this
```

**Step 4: Commit**

```bash
git add ansible/roles/ntp_audit/
git commit -m "feat(ntp_audit): scaffold role — defaults, meta"
```

---

### Task B2: Create audit script template

**Files:**
- Create: `ansible/roles/ntp_audit/templates/ntp-audit.sh.j2`

**Step 1: Create the script**

```bash
#!/usr/bin/env bash
# ntp-audit — NTP health and conflict audit
# Managed by Ansible (role: ntp_audit). Do not edit manually.
# Output: JSON to {{ ntp_audit_log_file }} + syslog via logger(1)

set -euo pipefail

LOG_FILE="{{ ntp_audit_log_file }}"
TIMESTAMP="$(date --iso-8601=seconds)"

# ---- chrony tracking ----
TRACKING_RAW="$(chronyc tracking 2>/dev/null || echo '')"

_extract() {
  echo "$TRACKING_RAW" | awk -F': ' "/^${1}/ {gsub(/ .*/, \"\", \$2); print \$2}"
}

NTP_STRATUM="$(_extract 'Stratum' || echo 'unknown')"
NTP_REFERENCE="$(_extract 'Reference ID' | awk '{print $1}' || echo 'unknown')"
NTP_OFFSET="$(echo "$TRACKING_RAW" | awk '/System time/ {print $4}' || echo 'unknown')"
NTP_FREQ_ERROR="$(echo "$TRACKING_RAW" | awk '/Frequency/ {print $3}' || echo 'unknown')"

if echo "$TRACKING_RAW" | grep -q 'Not synchronised'; then
  NTP_SYNC_STATUS="unsynchronised"
else
  NTP_SYNC_STATUS="ok"
fi

# ---- competing services ----
NTP_CONFLICT="none"
{% for svc in ntp_audit_competitor_services %}
if systemctl is-active --quiet {{ svc }} 2>/dev/null; then
  NTP_CONFLICT="{{ svc }}_active"
fi
{% endfor %}

# ---- PHC devices ----
NTP_PHC_STATUS="n/a"
NTP_PHC_DEVICE="none"
{% for dev in ntp_audit_phc_devices %}
if [ -c "{{ dev }}" ]; then
  NTP_PHC_STATUS="ok"
  NTP_PHC_DEVICE="{{ dev }}"
fi
{% endfor %}

# ---- kernel modules ----
NTP_MODULES_STATUS="n/a"
{% if ntp_audit_kernel_modules | length > 0 %}
NTP_MODULES_STATUS="ok"
{% for mod in ntp_audit_kernel_modules %}
if ! lsmod 2>/dev/null | grep -q "^{{ mod }}"; then
  NTP_MODULES_STATUS="{{ mod }}_missing"
fi
{% endfor %}
{% endif %}

# ---- compose JSON ----
JSON=$(cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "ntp_stratum": "${NTP_STRATUM}",
  "ntp_reference": "${NTP_REFERENCE}",
  "ntp_offset_s": "${NTP_OFFSET}",
  "ntp_freq_error_ppm": "${NTP_FREQ_ERROR}",
  "ntp_sync_status": "${NTP_SYNC_STATUS}",
  "ntp_conflict": "${NTP_CONFLICT}",
  "ntp_phc_status": "${NTP_PHC_STATUS}",
  "ntp_phc_device": "${NTP_PHC_DEVICE}",
  "ntp_modules_status": "${NTP_MODULES_STATUS}"
}
EOF
)

# ---- write JSON log ----
echo "$JSON" >> "$LOG_FILE"

# ---- syslog notification (works on all init systems) ----
SUMMARY="ntp_sync=${NTP_SYNC_STATUS} stratum=${NTP_STRATUM} conflict=${NTP_CONFLICT} phc=${NTP_PHC_STATUS}"
logger -t ntp-audit -p daemon.info "$SUMMARY"

# ---- exit non-zero on detected problems (triggers systemd failure unit if configured) ----
if [ "$NTP_SYNC_STATUS" = "unsynchronised" ] || [ "$NTP_CONFLICT" != "none" ] || [ "$NTP_PHC_STATUS" = "missing" ]; then
  logger -t ntp-audit -p daemon.warning "WARN: ${SUMMARY}"
fi

exit 0
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit.sh.j2
git commit -m "feat(ntp_audit): add audit script template (JSON log + syslog, init-agnostic)"
```

---

### Task B3: Create systemd unit templates

**Files:**
- Create: `ansible/roles/ntp_audit/templates/ntp-audit.service.j2`
- Create: `ansible/roles/ntp_audit/templates/ntp-audit.timer.j2`

**Step 1: Create ntp-audit.service.j2**

```ini
# Managed by Ansible (role: ntp_audit). Do not edit manually.
[Unit]
Description=NTP health and conflict audit
Documentation=https://github.com/your-org/bootstrap
After=chronyd.service
Wants=chronyd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ntp-audit
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ntp-audit
```

**Step 2: Create ntp-audit.timer.j2**

```ini
# Managed by Ansible (role: ntp_audit). Do not edit manually.
[Unit]
Description=Run NTP audit every {{ ntp_audit_interval_systemd }}
Documentation=https://github.com/your-org/bootstrap

[Timer]
OnCalendar={{ ntp_audit_interval_systemd }}
Persistent=true
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp_audit/templates/ntp-audit.service.j2 \
        ansible/roles/ntp_audit/templates/ntp-audit.timer.j2
git commit -m "feat(ntp_audit): add systemd timer/service unit templates"
```

---

### Task B4: Create Alloy config fragment template

**Files:**
- Create: `ansible/roles/ntp_audit/templates/alloy-ntp-audit.alloy.j2`

**Step 1: Create the file**

```hcl
// ntp-audit — Grafana Alloy configuration fragment
// Managed by Ansible (role: ntp_audit). Do not edit manually.
// Activated when Grafana Alloy is installed and loads conf.d/*.alloy

// NTP audit JSON log → Loki
loki.source.file "ntp_audit" {
  targets = [{
    __path__ = "{{ ntp_audit_log_file }}",
    job      = "ntp-audit",
    host     = constants.hostname,
  }]
  forward_to = [loki.write.default.receiver]
}

// Parse JSON fields from ntp-audit log as Loki structured metadata
loki.process "ntp_audit_json" {
  forward_to = [loki.write.default.receiver]

  stage.json {
    expressions = {
      ntp_stratum      = "ntp_stratum",
      ntp_sync_status  = "ntp_sync_status",
      ntp_conflict     = "ntp_conflict",
      ntp_phc_status   = "ntp_phc_status",
      ntp_offset_s     = "ntp_offset_s",
    }
  }

  stage.labels {
    values = {
      ntp_sync_status = "",
      ntp_conflict    = "",
      ntp_phc_status  = "",
    }
  }
}

// chrony structured logs → Loki (tracking, measurements, statistics)
loki.source.file "chrony_logs" {
  targets = [{
    __path__ = "{{ ntp_logdir }}/*.log",
    job      = "chrony",
    host     = constants.hostname,
  }]
  forward_to = [loki.write.default.receiver]
}

// Kernel NTP metrics via node_exporter timex collector → Prometheus
prometheus.exporter.unix "ntp_timex" {
  enable_collectors = ["timex"]
}

prometheus.scrape "ntp_timex" {
  targets    = prometheus.exporter.unix.ntp_timex.targets
  forward_to = [prometheus.remote_write.default.receiver]
  job_name   = "ntp-timex"
}
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/templates/alloy-ntp-audit.alloy.j2
git commit -m "feat(ntp_audit): add Grafana Alloy config fragment (JSON log + chrony logs + timex)"
```

---

### Task B5: Create Loki ruler alert rules template

**Files:**
- Create: `ansible/roles/ntp_audit/templates/loki-ntp-audit-rules.yaml.j2`

**Step 1: Create the file**

```yaml
# ntp-audit — Loki ruler alert rules
# Managed by Ansible (role: ntp_audit). Do not edit manually.
# Deploy path: {{ ntp_audit_loki_rules_dir }}/ntp-audit-rules.yaml

groups:
  - name: ntp-audit
    interval: 5m
    rules:

      - alert: NtpCompetingDaemon
        expr: |
          count_over_time(
            {job="ntp-audit", ntp_conflict!="none"} [10m]
          ) > 0
        for: 0m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "Competing time sync daemon active alongside chrony"
          description: >-
            Host {{ "{{ $labels.host }}" }}: a competing NTP daemon is running
            (ntp_conflict={{ "{{ $labels.ntp_conflict }}" }}).
            This causes clock discipline conflicts. Stop the competing daemon.

      - alert: NtpPHCMissing
        expr: |
          count_over_time(
            {job="ntp-audit", ntp_phc_status="missing"} [10m]
          ) > 0
        for: 0m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "PTP hardware clock device missing on VM"
          description: >-
            Host {{ "{{ $labels.host }}" }}: PHC device expected but not present.
            Check hypervisor guest tools and kernel module (ptp_kvm / hv_utils).

      - alert: NtpUnsynchronised
        expr: |
          count_over_time(
            {job="ntp-audit", ntp_sync_status="unsynchronised"} [15m]
          ) > 0
        for: 5m
        labels:
          severity: critical
          team: ops
        annotations:
          summary: "chrony is not synchronised"
          description: >-
            Host {{ "{{ $labels.host }}" }}: chrony has been unsynchronised for > 15 minutes.
            Check internet connectivity and NTP server reachability.

      - alert: NtpHighOffset
        expr: |
          {job="ntp-audit"}
            | json
            | ntp_offset_s | float > {{ ntp_audit_alert_offset_threshold }}
        for: 10m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "NTP clock offset exceeds {{ ntp_audit_alert_offset_threshold }}s"
          description: >-
            Host {{ "{{ $labels.host }}" }}: clock offset is too large.
            May indicate VM clock disruption or NTP source problems.

      - alert: NtpClockStep
        expr: |
          count_over_time(
            {job="chrony"} |= "System clock was stepped" [5m]
          ) > 0
        for: 0m
        labels:
          severity: info
          team: ops
        annotations:
          summary: "chrony performed a clock step"
          description: >-
            Host {{ "{{ $labels.host }}" }}: a large time correction was applied (makestep).
            Normal after VM resume or first sync. Investigate if recurring.

      - alert: NtpHighStratum
        expr: |
          {job="ntp-audit"}
            | json
            | ntp_stratum | int > {{ ntp_audit_alert_stratum_max }}
        for: 15m
        labels:
          severity: warning
          team: ops
        annotations:
          summary: "NTP stratum too high (> {{ ntp_audit_alert_stratum_max }})"
          description: >-
            Host {{ "{{ $labels.host }}" }}: stratum {{ "{{ $labels.ntp_stratum }}" }}.
            NTP source quality is degraded.
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp_audit/templates/loki-ntp-audit-rules.yaml.j2
git commit -m "feat(ntp_audit): add Loki ruler alert rules (6 alerts: conflict, PHC, sync, offset, step, stratum)"
```

---

### Task B6: Create tasks/main.yml

**Files:**
- Create: `ansible/roles/ntp_audit/tasks/main.yml`

**Step 1: Create the file**

```yaml
---
# === ntp_audit — runtime NTP health and conflict audit ===
# Init-system agnostic: systemd timer on systemd, cron on others.
# Output: JSON → /var/log/ntp-audit/audit.log + syslog via logger(1)

- name: ntp_audit role
  when: ntp_audit_enabled | bool
  tags: ['ntp_audit']
  block:

    # ======================================================================
    # ---- Log directory ----
    # ======================================================================

    - name: Create audit log directory
      ansible.builtin.file:
        path: "{{ ntp_audit_log_dir }}"
        state: directory
        owner: root
        group: root
        mode: "0755"
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Audit script ----
    # ======================================================================

    - name: Deploy ntp-audit script
      ansible.builtin.template:
        src: ntp-audit.sh.j2
        dest: /usr/local/bin/ntp-audit
        owner: root
        group: root
        mode: "0755"
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Scheduler: systemd timer (systemd) ----
    # ======================================================================

    - name: Deploy ntp-audit systemd service unit
      ansible.builtin.template:
        src: ntp-audit.service.j2
        dest: /etc/systemd/system/ntp-audit.service
        owner: root
        group: root
        mode: "0644"
      notify: Reload systemd
      when: ansible_facts['service_mgr'] == 'systemd'
      tags: ['ntp_audit']

    - name: Deploy ntp-audit systemd timer unit
      ansible.builtin.template:
        src: ntp-audit.timer.j2
        dest: /etc/systemd/system/ntp-audit.timer
        owner: root
        group: root
        mode: "0644"
      notify: Reload systemd
      when: ansible_facts['service_mgr'] == 'systemd'
      tags: ['ntp_audit']

    - name: Enable and start ntp-audit timer (systemd)
      ansible.builtin.systemd:
        name: ntp-audit.timer
        enabled: true
        state: started
        daemon_reload: true
      when: ansible_facts['service_mgr'] == 'systemd'
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Scheduler: cron (non-systemd) ----
    # ======================================================================

    - name: Deploy ntp-audit cron job (non-systemd)
      ansible.builtin.cron:
        name: "ntp-audit"
        job: "/usr/local/bin/ntp-audit"
        minute: "{{ ntp_audit_interval_cron.split()[0] }}"
        hour: "{{ ntp_audit_interval_cron.split()[1] }}"
        day: "{{ ntp_audit_interval_cron.split()[2] }}"
        month: "{{ ntp_audit_interval_cron.split()[3] }}"
        weekday: "{{ ntp_audit_interval_cron.split()[4] }}"
        user: root
      when: ansible_facts['service_mgr'] != 'systemd'
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Alloy config fragment (pre-deployed, no Alloy dependency) ----
    # ======================================================================

    - name: Create Alloy conf.d directory if missing
      ansible.builtin.file:
        path: "{{ ntp_audit_alloy_config_dir }}"
        state: directory
        owner: root
        group: root
        mode: "0755"
      when: ntp_audit_alloy_config_dir | length > 0
      tags: ['ntp_audit']

    - name: Deploy Alloy config fragment for ntp-audit
      ansible.builtin.template:
        src: alloy-ntp-audit.alloy.j2
        dest: "{{ ntp_audit_alloy_config_dir }}/ntp-audit.alloy"
        owner: root
        group: root
        mode: "0644"
      when: ntp_audit_alloy_config_dir | length > 0
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Loki ruler rules (pre-deployed, no Loki dependency) ----
    # ======================================================================

    - name: Create Loki rules directory if missing
      ansible.builtin.file:
        path: "{{ ntp_audit_loki_rules_dir }}"
        state: directory
        owner: root
        group: root
        mode: "0755"
      when: ntp_audit_loki_rules_dir | length > 0
      tags: ['ntp_audit']

    - name: Deploy Loki alert rules for ntp-audit
      ansible.builtin.template:
        src: loki-ntp-audit-rules.yaml.j2
        dest: "{{ ntp_audit_loki_rules_dir }}/ntp-audit-rules.yaml"
        owner: root
        group: root
        mode: "0644"
      when: ntp_audit_loki_rules_dir | length > 0
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Run once immediately after deploy ----
    # ======================================================================

    - name: Run ntp-audit immediately (first run)
      ansible.builtin.command:
        cmd: /usr/local/bin/ntp-audit
      changed_when: false
      failed_when: false
      tags: ['ntp_audit']

    # ======================================================================
    # ---- Verify ----
    # ======================================================================

    - name: Assert audit log file exists after first run
      ansible.builtin.stat:
        path: "{{ ntp_audit_log_file }}"
      register: _ntp_audit_log_stat
      tags: ['ntp_audit']

    - name: Assert ntp-audit log was written
      ansible.builtin.assert:
        that:
          - _ntp_audit_log_stat.stat.exists
          - _ntp_audit_log_stat.stat.size > 0
        fail_msg: "ntp-audit did not write to {{ ntp_audit_log_file }}"
      tags: ['ntp_audit']
```

**Step 2: Create handlers/main.yml**

```yaml
---
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
  when: ansible_facts['service_mgr'] == 'systemd'
  listen: "Reload systemd"
```

**Step 3: Syntax check**

```bash
ansible-lint ansible/roles/ntp_audit/tasks/main.yml
```

**Step 4: Commit**

```bash
git add ansible/roles/ntp_audit/tasks/main.yml ansible/roles/ntp_audit/handlers/main.yml
git commit -m "feat(ntp_audit): add tasks/main.yml — script deploy, systemd timer, cron, alloy/loki pre-config, first run"
```

---

### Task B7: Add molecule tests for ntp_audit

**Files:**
- Create: `ansible/roles/ntp_audit/molecule/default/molecule.yml`
- Create: `ansible/roles/ntp_audit/molecule/default/converge.yml`
- Create: `ansible/roles/ntp_audit/molecule/default/verify.yml`

**Step 1: molecule.yml** (mirror ntp role)

```yaml
---
driver:
  name: default
  options:
    managed: false

platforms:
  - name: localhost

provisioner:
  name: ansible
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
  playbooks:
    converge: converge.yml
    verify: verify.yml
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Step 2: converge.yml**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  pre_tasks:
    - name: Ensure chrony is installed (ntp_audit depends on chronyc)
      ansible.builtin.package:
        name: chrony
        state: present

    - name: Ensure chronyd is running
      ansible.builtin.service:
        name: chronyd
        state: started
        enabled: true

  roles:
    - role: ntp_audit
```

**Step 3: verify.yml**

```yaml
---
- name: Verify ntp_audit
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  tasks:

    - name: Assert ntp-audit script exists and is executable
      ansible.builtin.stat:
        path: /usr/local/bin/ntp-audit
      register: _v_script

    - name: Verify ntp-audit script
      ansible.builtin.assert:
        that:
          - _v_script.stat.exists
          - _v_script.stat.executable
        fail_msg: "/usr/local/bin/ntp-audit missing or not executable"

    - name: Assert audit log directory exists
      ansible.builtin.stat:
        path: /var/log/ntp-audit
      register: _v_logdir

    - name: Verify log directory
      ansible.builtin.assert:
        that:
          - _v_logdir.stat.exists
          - _v_logdir.stat.isdir
        fail_msg: "/var/log/ntp-audit directory missing"

    - name: Assert audit log file exists (written on first run)
      ansible.builtin.stat:
        path: /var/log/ntp-audit/audit.log
      register: _v_logfile

    - name: Verify audit log written
      ansible.builtin.assert:
        that:
          - _v_logfile.stat.exists
          - _v_logfile.stat.size > 0
        fail_msg: "audit.log missing or empty — ntp-audit first run failed"

    - name: Read last line of audit log
      ansible.builtin.command:
        cmd: tail -1 /var/log/ntp-audit/audit.log
      register: _v_last_line
      changed_when: false

    - name: Assert audit log contains valid JSON with required keys
      ansible.builtin.assert:
        that:
          - _v_last_line.stdout | from_json | community.general.json_query('ntp_sync_status') is defined
          - _v_last_line.stdout | from_json | community.general.json_query('ntp_conflict') is defined
          - _v_last_line.stdout | from_json | community.general.json_query('ntp_phc_status') is defined
          - _v_last_line.stdout | from_json | community.general.json_query('timestamp') is defined
        fail_msg: "audit.log last line is not valid JSON or missing required keys"

    - name: Assert systemd timer is active (systemd only)
      ansible.builtin.service_facts:
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Verify ntp-audit.timer is enabled
      ansible.builtin.assert:
        that:
          - "'ntp-audit.timer' in ansible_facts.services"
          - ansible_facts.services['ntp-audit.timer'].status == 'enabled'
        fail_msg: "ntp-audit.timer not enabled"
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert Alloy config fragment deployed
      ansible.builtin.stat:
        path: /etc/alloy/conf.d/ntp-audit.alloy
      register: _v_alloy

    - name: Verify Alloy fragment
      ansible.builtin.assert:
        that:
          - _v_alloy.stat.exists
          - _v_alloy.stat.size > 0
        fail_msg: "Alloy config fragment /etc/alloy/conf.d/ntp-audit.alloy missing"

    - name: Assert Loki rules deployed
      ansible.builtin.stat:
        path: /etc/loki/rules/fake/ntp-audit-rules.yaml
      register: _v_loki

    - name: Verify Loki rules
      ansible.builtin.assert:
        that:
          - _v_loki.stat.exists
          - _v_loki.stat.size > 0
        fail_msg: "Loki alert rules /etc/loki/rules/fake/ntp-audit-rules.yaml missing"

    - name: Show result
      ansible.builtin.debug:
        msg: "ntp_audit check passed: script, timer, log written, alloy/loki configs deployed"
```

**Step 4: Run molecule**

```bash
task test-ntp-audit
```
Expected: all assertions pass

**Step 5: Commit**

```bash
git add ansible/roles/ntp_audit/molecule/
git commit -m "test(ntp_audit): add molecule scenario — script, timer, log, alloy/loki assertions"
```

---

### Task B8: Add to Taskfile and workstation.yml

**Files:**
- Modify: `Taskfile.yml`
- Modify: `ansible/playbooks/workstation.yml`

**Step 1: Add Taskfile entry**

Find the `test-ntp:` block in `Taskfile.yml` and add after it:

```yaml
  test-ntp-audit:
    desc: "Run molecule tests for ntp_audit"
    deps: [_ensure-venv, _check-vault]
    dir: '{{.ANSIBLE_DIR}}/roles/ntp_audit'
    env:
      MOLECULE_PROJECT_DIRECTORY: '{{.ANSIBLE_DIR}}'
    cmds:
      - '{{.PREFIX}} molecule test'
```

Also add `test-ntp-audit` to the `test-all` task dependencies.

**Step 2: Add role to workstation.yml**

After the `ntp` role block (lines 43-45), add:

```yaml
    - role: ntp_audit
      tags: [system, ntp, ntp_audit]
      when: ntp_enabled | default(true) and ntp_audit_enabled | default(true)
```

**Step 3: Syntax check**

```bash
ansible-playbook ansible/playbooks/workstation.yml --syntax-check
```

**Step 4: Commit**

```bash
git add Taskfile.yml ansible/playbooks/workstation.yml
git commit -m "feat: add ntp_audit role to workstation.yml and Taskfile"
```

---

## Verification: Full stack test

**Run on remote VM:**

```bash
# 1. Syntax check entire playbook
ansible-playbook ansible/playbooks/workstation.yml --syntax-check

# 2. Dry run ntp + ntp_audit tags
ansible-playbook ansible/playbooks/workstation.yml --tags "ntp,ntp_audit" --check

# 3. Molecule: ntp role
task test-ntp

# 4. Molecule: ntp_audit role
task test-ntp-audit

# 5. Verify audit log on live system
tail -f /var/log/ntp-audit/audit.log | python3 -m json.tool

# 6. Check Alloy fragment is valid (when Alloy installed)
# alloy fmt /etc/alloy/conf.d/ntp-audit.alloy

# 7. Check Loki rules syntax (when Loki installed)
# promtool check rules /etc/loki/rules/fake/ntp-audit-rules.yaml
```

---

## Alloy integration checklist (when Alloy role arrives)

When a future `alloy` role is added to the project:

- [ ] Alloy role loads all `*.alloy` files from `/etc/alloy/conf.d/` (pattern: `config.alloy` imports conf.d/)
- [ ] `ntp-audit.alloy` fragment is already deployed — zero additional config needed
- [ ] Loki ruler rules at `/etc/loki/rules/fake/ntp-audit-rules.yaml` activate automatically
- [ ] Full alerting works on first Alloy run
