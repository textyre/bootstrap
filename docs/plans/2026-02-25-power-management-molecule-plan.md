# Plan: power_management role -- Molecule testing (docker + vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/power_management/`

---

## 1. Current State

### What the role does

The `power_management` role is a comprehensive power management stack that auto-detects
laptop vs desktop via DMI chassis type and applies the appropriate strategy:

**Laptop path (TLP):**
- Installs `tlp` + `tlp-rdw` (pacman on Arch, apt on Debian/Ubuntu)
- Deploys `/etc/tlp.conf` from template with backup/rollback (block/rescue)
- Masks conflicting services: `power-profiles-daemon`, `auto-cpufreq`, `systemd-rfkill` (Arch)
- Enables and starts `tlp.service`
- Configures per-subsystem AC/battery profiles: CPU governor, turbo boost, EPP, disk APM,
  SATA link power, USB autosuspend, PCIe ASPM, WiFi power, sound, runtime PM
- Optional battery charge thresholds (ThinkPad/Dell hardware)

**Desktop path (cpupower + udev):**
- Installs `cpupower` (pacman on Arch, `linux-tools-*` on Debian)
- Sets CPU governor via `cpupower frequency-set`
- Persists governor via udev rule (`/etc/udev/rules.d/50-cpu-governor.rules`),
  systemd cpupower service dropin, or oneshot (no persistence)
- Masks `power-profiles-daemon` and `auto-cpufreq`

**Both paths (systemd):**
- Deploys `/etc/systemd/logind.conf` -- lid switch, power key, idle actions
- Deploys `/etc/systemd/sleep.conf` -- hibernate mode, suspend state
- Collects system power facts into `power_management_status` dict
- Post-deploy assertions: TLP running, PPD masked, governor correct, sleep.conf correct,
  logind.conf correct, charge thresholds applied (6 checks, controlled by `power_management_assert_strict`)
- Drift detection: compares current state against `/var/lib/ansible-power-management/last_state.json`
- Audit: deploys `/usr/local/bin/power-audit.sh` + systemd timer (or cron fallback)

**Task execution order** (`tasks/main.yml`):
1. `detect.yml` -- DMI chassis, CPU vendor, init system
2. `preflight.yml` -- swap check for hibernate, SSH lockout warning
3. `conflicts.yml` -- mask power-profiles-daemon, auto-cpufreq
4. `install.yml` -- dispatches to `install-archlinux.yml` or `install-debian.yml`
5. `tlp.yml` -- TLP config with block/rescue rollback (laptop only)
6. `governor.yml` -- cpupower + persistence (desktop only)
7. `sleep.yml` -- systemd sleep.conf (systemd only)
8. `logind.yml` -- systemd logind.conf (systemd only)
9. `collect_facts.yml` -- read /sys/ for governor, battery, TLP status
10. `assert.yml` -- post-deploy effectiveness checks
11. `drift_detection.yml` -- compare with previous state
12. `audit.yml` -- deploy audit script + timer/cron
13. `report.yml` -- summary debug output

**Templates:**
- `tlp.conf.j2` -- full TLP configuration (CPU, disk, USB, PCIe, WiFi, sound, runtime PM, battery thresholds)
- `logind.conf.j2` -- all 8 logind power actions
- `sleep.conf.j2` -- HibernateMode, optional SuspendState and HibernateDelaySec
- `50-cpu-governor.rules.j2` -- udev rule for governor persistence
- `power-audit.sh.j2` -- audit script (CPU governors, TLP status, battery health, conflicts, thresholds)
- `power-audit.service.j2` -- systemd oneshot unit
- `power-audit.timer.j2` -- systemd daily timer

**Handlers:**
- `restart tlp` -- `listen:` directive, service restart (guarded by `power_management_is_laptop`)
- `reload systemd-logind` -- `listen:` directive, systemd reload (guarded by init == systemd)
- `reload udev rules` -- `listen:` directive, `udevadm control --reload-rules`

**Variables:** 50+ variables with `power_management_` prefix in `defaults/main.yml`.

**OS support:** ArchLinux and Debian declared in `meta/main.yml`. Install tasks exist for both
(`install-archlinux.yml`, `install-debian.yml`).

### What tests exist now

Single `molecule/default/` scenario:
- **Driver:** `default` (localhost, managed: false)
- **Provisioner:** Ansible with vault password, local connection
- **converge.yml:** Asserts `os_family == Archlinux`, loads vault.yml, applies `power_management` role
- **verify.yml:** 12 check groups:
  1. cpupower package installed (check_mode idempotency)
  2. `/etc/systemd/sleep.conf` exists and contains `HibernateMode`
  3. DMI chassis type detection + laptop fact derivation
  4. TLP installed, config exists, service enabled (laptop conditional)
  5. CPU governor readable from `/sys/` and non-empty
  6. logind.conf contains `HandleLidSwitch=`
  7. power-audit.sh exists with mode `0755`
  8. power-audit.timer enabled (via `service_facts`)
  9. Drift state directory exists with mode `0700`
  10. Summary debug message
- **Test sequence:** syntax, converge, idempotence, verify (no create/destroy -- localhost)

### Gaps in current tests

- **No cross-platform testing** -- converge.yml hard-asserts Arch-only
- **No Docker scenario** -- cannot run in CI
- **No Vagrant scenario** -- no real-VM testing with multiple distros
- **Vault dependency in converge/verify** -- role has no vault variables; unnecessary coupling
- **No verification of TLP config content** -- only checks file existence
- **No verification of logind.conf content values** -- only checks `HandleLidSwitch=` substring
- **No verification of udev rule deployment** (desktop path)
- **No audit script content verification**
- **No power-audit.service unit verification**
- **`_power_management_supported_os` undefined** -- `install.yml` line 13 references
  `_power_management_supported_os` but `defaults/main.yml` defines `power_management_supported_os`
  (no leading underscore). This is a latent bug that will cause the `include_tasks` to be
  silently skipped on all OS families.

---

## 2. Cross-Platform Analysis

### Power management tools availability

| Component | Arch Linux | Ubuntu 24.04 |
|-----------|-----------|--------------|
| TLP | `tlp`, `tlp-rdw` (pacman) | `tlp`, `tlp-rdw` (apt) |
| cpupower | `cpupower` (pacman) | `linux-tools-common` + `linux-tools-$(uname -r)` or `linux-cpupower` |
| systemd-logind | always present | always present |
| sleep.conf | always present | always present |
| power-profiles-daemon | often pre-installed | pre-installed on desktop installs |
| udevadm | always present | always present |

### Behavioral differences

| Aspect | Arch | Ubuntu |
|--------|------|--------|
| Package install module | `community.general.pacman` | `ansible.builtin.apt` |
| cpupower package name | `cpupower` | `linux-tools-$(uname -r)` or `linux-cpupower` fallback |
| systemd-rfkill masking | yes (Arch-specific in `install-archlinux.yml`) | no (not in `install-debian.yml`) |
| cpupower binary path | `/usr/bin/cpupower` | `/usr/bin/cpupower` (from linux-tools-common) |
| DMI chassis_type | available in VMs and containers (if `/sys/class/dmi/id/` mounted) | same |
| `/proc/cpuinfo` | always present | always present |
| `/sys/devices/system/cpu/cpu0/cpufreq/` | present on real hardware, may be absent in containers | same |

### Container vs VM implications

Power management is fundamentally hardware-coupled. In containers:
- `/sys/class/dmi/id/chassis_type` may be absent or show host value
- `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` likely absent (no cpufreq driver loaded)
- `/proc/cpuinfo` present (shows host CPU)
- TLP installs but cannot function without hardware interfaces
- `cpupower frequency-set` fails without cpufreq driver
- Battery sysfs entries absent
- logind.conf and sleep.conf deploy fine (just config files)
- udev rules deploy fine (file deployment, not runtime functionality)
- systemd timers work normally

In VMs:
- DMI chassis_type available (QEMU reports type "1" = Other -- detected as desktop)
- `/sys/devices/system/cpu/cpu0/cpufreq/` present if `acpi-cpufreq` or `kvm-cpufreq` driver loaded
- No battery, no charge thresholds
- TLP installs but detects as desktop (no battery)
- logind, sleep.conf, udev all functional

---

## 3. Shared Migration

### Current default/ playbooks to move

**converge.yml** changes needed:
- Remove Arch-only assertion (role supports Arch + Debian)
- Remove vault.yml vars_files (role has no vault variables)
- Force desktop mode with `power_management_device_type: desktop` (containers/VMs have no battery,
  DMI reports non-laptop chassis)
- Disable strict assertions (hardware checks will fail in containers: no cpufreq, no battery)
- Disable audit battery checks (no battery in test environments)

**verify.yml** changes needed:
- Remove vault.yml vars_files
- Make all hardware-dependent checks conditional (governor from `/sys/`, TLP service, battery)
- Add OS-conditional package checks (cpupower on Arch, linux-cpupower on Debian)
- Add config content verification (not just existence)
- Add udev rule file verification (desktop path)
- Add audit unit file verification

### New shared/ playbook design

`molecule/shared/converge.yml`:
```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: power_management
      vars:
        power_management_device_type: desktop
        power_management_assert_strict: false
        power_management_audit_battery: false
```

Key decisions:
- Force `desktop` mode because containers and QEMU VMs report DMI chassis_type that maps to
  desktop (type "1" = Other). TLP laptop path requires real laptop hardware or
  `power_management_device_type: laptop` override.
- `assert_strict: false` because `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` will not
  exist in Docker containers, causing the governor assertion to fail.
- `audit_battery: false` because no battery in test environments.

`molecule/shared/verify.yml`: See section 7 for full design.

---

## 4. Docker/VM Testing Challenge

### What CAN be tested in Docker

| Component | Testable? | How |
|-----------|-----------|-----|
| sleep.conf deployed with correct content | Yes | slurp + assert |
| logind.conf deployed with correct content | Yes | slurp + assert |
| udev rule deployed with correct content | Yes | slurp + assert (file content) |
| power-audit.sh deployed, executable | Yes | stat + mode check |
| power-audit.service unit deployed | Yes | stat + content check |
| power-audit.timer enabled | Yes | systemctl is-enabled |
| drift state directory created with mode 0700 | Yes | stat |
| cpupower package installed (Arch) | Yes | package_facts |
| power-profiles-daemon masked | Yes | systemctl is-masked (if installed) |
| auto-cpufreq masked | Yes | systemctl is-masked (if installed) |
| Template content correctness | Yes | slurp + regex assertions |

### What CANNOT be tested in Docker

| Component | Why |
|-----------|-----|
| CPU governor actually set | No cpufreq driver in containers |
| TLP running and managing power | No hardware interfaces |
| Battery charge thresholds | No battery hardware |
| cpupower frequency-set command | No cpufreq subsystem |
| Actual suspend/hibernate behavior | No real power management |
| udev rule runtime effect | udev may not process rules in containers |
| systemd-logind actual behavior | logind may not be fully functional |

### What CAN additionally be tested in Vagrant VMs

| Component | Testable? | Notes |
|-----------|-----------|-------|
| CPU governor set via cpupower | Maybe | Requires `acpi-cpufreq` or equivalent driver in VM |
| udev rule loaded | Yes | udevadm works in VMs |
| logind behavior (loginctl) | Yes | Full systemd stack |
| TLP service runs | With `device_type: laptop` override | No real battery, but service starts |
| sleep.conf validated by systemd | Yes | `systemd-analyze cat-config` |
| cpupower service (persist=service) | Yes | Full systemd |

---

## 5. Docker Scenario

### `molecule/docker/molecule.yml`

```yaml
---
driver:
  name: docker

platforms:
  - name: Archlinux-systemd
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/bootstrap/arch-systemd:latest}"
    pre_build_image: true
    command: /usr/lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs: [/run, /tmp]
    privileged: true
    dns_servers: [8.8.8.8, 8.8.4.4]

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

### `molecule/docker/prepare.yml`

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true
```

### Docker-specific concerns

1. **cpupower installation succeeds** but `cpupower frequency-set` will fail at runtime because
   the container has no cpufreq driver. The role handles this gracefully: `governor.yml` reads
   `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` with `failed_when: false`, and the
   `cpupower frequency-set` command is guarded by
   `when: power_management_current_governor != power_management_cpu_governor` -- since
   `power_management_current_governor` will be `unknown`, and the configured governor is
   `schedutil`, the condition is true, but the command will fail. This triggers a play failure.

   **Mitigation:** The converge uses `power_management_assert_strict: false`. However, the
   `cpupower frequency-set` task in `governor.yml` line 42 has
   `failed_when: power_management_governor_set.rc != 0` which is NOT gated by `assert_strict`.
   This means **converge will fail in Docker** on the governor set command.

   **Required fix for Docker compatibility:** Either:
   - (a) Add `failed_when: false` to the cpupower command when in a container/test environment
   - (b) Skip the cpupower set command when `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
     doesn't exist (check `power_management_current_governor != 'unknown'`)
   - (c) Add a molecule-specific variable override: `power_management_governor_persist: oneshot`
     won't help because the `cpupower frequency-set` still runs

   **Recommended approach (b):** Add a condition to `governor.yml` line 39:
   ```yaml
   when:
     - not power_management_is_laptop
     - power_management_current_governor != 'unknown'
     - power_management_current_governor != power_management_cpu_governor
   ```
   This is the safest fix -- if the governor cannot be read, skip trying to set it. The udev
   rule still deploys (it's just a file).

2. **power-audit.timer** -- systemd timers work in privileged containers with systemd PID 1.
   No issues expected.

3. **power-profiles-daemon and auto-cpufreq masking** -- these services likely don't exist in
   the container image. The tasks use `failed_when: false`, so this is safe.

4. **Idempotence** -- the `cpupower frequency-set` command uses `changed_when` based on
   governor comparison. If the governor is `unknown` (container), this will report changed
   on every run (assuming the fix from point 1 makes it `failed_when: false`). The udev rule
   template deployment should be idempotent. All template tasks should be idempotent.

   **Potential idempotence issues:**
   - `cpupower frequency-set` reports changed if `current != target` and `current == unknown`
   - TLP backup uses `ansible_date_time.epoch` which changes between runs (but TLP path is
     skipped in desktop mode)
   - Drift detection writes `last_state.json` on each run -- content may differ if governor
     reads change between runs (unlikely in container)

---

## 6. Vagrant Scenario

### `molecule/vagrant/molecule.yml`

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: generic/arch
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: bento/ubuntu-24.04
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

### `molecule/vagrant/prepare.yml`

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Bootstrap Python on Arch (raw -- no Python required)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts
      ansible.builtin.gather_facts:

    - name: Refresh pacman keyring on Arch (generic/arch box has stale keys)
      ansible.builtin.shell: |
        sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
        pacman -Sy --noconfirm archlinux-keyring
        sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
        pacman-key --populate archlinux
      args:
        executable: /bin/bash
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade on Arch (ensures openssl/ssl compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Load acpi-cpufreq kernel module (VM may not load it by default)
      ansible.builtin.command: modprobe acpi-cpufreq
      failed_when: false
      changed_when: false

    - name: Load cpufreq_schedutil kernel module
      ansible.builtin.command: modprobe cpufreq_schedutil
      failed_when: false
      changed_when: false
```

### Vagrant-specific concerns

1. **DMI chassis_type in QEMU VMs** -- QEMU reports chassis_type "1" (Other), which is NOT in
   the laptop chassis types list. The role will detect as desktop. This is correct behavior
   for testing the desktop path. To test the laptop path, override
   `power_management_device_type: laptop` in a separate converge or test scenario.

2. **cpufreq in VMs** -- KVM guests may or may not have a cpufreq driver depending on host
   configuration. The prepare.yml attempts `modprobe acpi-cpufreq` but this may fail if the
   kernel doesn't support it. The `failed_when: false` ensures this doesn't block the test.
   If cpufreq is unavailable, the same `unknown` governor logic applies as in Docker.

3. **Ubuntu cpupower package** -- On Ubuntu 24.04, the role installs
   `linux-tools-{{ ansible_kernel }}`. In a Vagrant VM, this kernel-versioned package should
   exist. If not, the fallback to `linux-cpupower` + `linux-tools-common` handles it.

4. **No battery in VM** -- Battery-related checks (TLP battery status, charge thresholds,
   battery audit) will all return N/A. The converge uses `power_management_audit_battery: false`.

---

## 7. Verify.yml Design

The verify playbook must work across Docker containers and Vagrant VMs on both Arch and Ubuntu.
All hardware-dependent checks are conditional.

### `molecule/shared/verify.yml`

```yaml
---
- name: Verify power_management role
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Load role defaults for variable reference in assertions
    _pm_verify_defaults: "{{ lookup('file', molecule_yml | dirname + '/../../defaults/main.yml') | from_yaml }}"

  tasks:

    # ==== Environment Detection ====

    - name: Read DMI chassis type
      ansible.builtin.slurp:
        src: /sys/class/dmi/id/chassis_type
      register: pm_verify_chassis
      failed_when: false

    - name: Set laptop detection fact
      ansible.builtin.set_fact:
        pm_verify_is_laptop: >-
          {{ pm_verify_chassis is succeeded and
             (pm_verify_chassis.content | b64decode | trim) in ['8', '9', '10', '14', '30', '31', '32'] }}

    - name: Check if cpufreq is available
      ansible.builtin.stat:
        path: /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
      register: pm_verify_cpufreq_available

    # ==== Package Checks ====

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    - name: Assert cpupower is installed (Arch)
      ansible.builtin.assert:
        that: "'cpupower' in ansible_facts.packages"
        fail_msg: "cpupower package not installed"
        success_msg: "cpupower package installed"
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Assert linux-cpupower or linux-tools-common is installed (Debian)
      ansible.builtin.assert:
        that: >-
          'linux-cpupower' in ansible_facts.packages or
          'linux-tools-common' in ansible_facts.packages
        fail_msg: "Neither linux-cpupower nor linux-tools-common installed"
        success_msg: "cpupower tooling installed (Debian)"
      when: ansible_facts['os_family'] == 'Debian'

    # ==== Config File Deployment Checks ====

    # ---- sleep.conf ----

    - name: Stat /etc/systemd/sleep.conf
      ansible.builtin.stat:
        path: /etc/systemd/sleep.conf
      register: pm_verify_sleep

    - name: Assert sleep.conf exists with correct permissions
      ansible.builtin.assert:
        that:
          - pm_verify_sleep.stat.exists
          - pm_verify_sleep.stat.pw_name == 'root'
          - pm_verify_sleep.stat.gr_name == 'root'
          - pm_verify_sleep.stat.mode == '0644'
        fail_msg: "sleep.conf missing or wrong permissions"
        success_msg: "sleep.conf deployed with correct permissions"

    - name: Read sleep.conf content
      ansible.builtin.slurp:
        src: /etc/systemd/sleep.conf
      register: pm_verify_sleep_content

    - name: Set sleep.conf text fact
      ansible.builtin.set_fact:
        pm_verify_sleep_text: "{{ pm_verify_sleep_content.content | b64decode }}"

    - name: Assert sleep.conf contains Ansible header
      ansible.builtin.assert:
        that: "'Managed by Ansible' in pm_verify_sleep_text"
        fail_msg: "sleep.conf missing Ansible managed header"

    - name: Assert sleep.conf contains HibernateMode=platform
      ansible.builtin.assert:
        that: "'HibernateMode=platform' in pm_verify_sleep_text"
        fail_msg: "sleep.conf does not contain HibernateMode=platform"
        success_msg: "sleep.conf HibernateMode=platform confirmed"

    - name: Assert sleep.conf contains [Sleep] section
      ansible.builtin.assert:
        that: "'[Sleep]' in pm_verify_sleep_text"
        fail_msg: "sleep.conf missing [Sleep] section header"

    # ---- logind.conf ----

    - name: Stat /etc/systemd/logind.conf
      ansible.builtin.stat:
        path: /etc/systemd/logind.conf
      register: pm_verify_logind

    - name: Assert logind.conf exists with correct permissions
      ansible.builtin.assert:
        that:
          - pm_verify_logind.stat.exists
          - pm_verify_logind.stat.pw_name == 'root'
          - pm_verify_logind.stat.gr_name == 'root'
          - pm_verify_logind.stat.mode == '0644'
        fail_msg: "logind.conf missing or wrong permissions"
        success_msg: "logind.conf deployed with correct permissions"

    - name: Read logind.conf content
      ansible.builtin.slurp:
        src: /etc/systemd/logind.conf
      register: pm_verify_logind_content

    - name: Set logind.conf text fact
      ansible.builtin.set_fact:
        pm_verify_logind_text: "{{ pm_verify_logind_content.content | b64decode }}"

    - name: Assert logind.conf contains expected directives
      ansible.builtin.assert:
        that:
          - "'HandleLidSwitch=suspend' in pm_verify_logind_text"
          - "'HandleLidSwitchExternalPower=suspend' in pm_verify_logind_text"
          - "'HandleLidSwitchDocked=ignore' in pm_verify_logind_text"
          - "'HandlePowerKey=poweroff' in pm_verify_logind_text"
          - "'HandleSuspendKey=suspend' in pm_verify_logind_text"
          - "'HandleHibernateKey=ignore' in pm_verify_logind_text"
          - "'IdleAction=ignore' in pm_verify_logind_text"
          - "'IdleActionSec=30min' in pm_verify_logind_text"
        fail_msg: "logind.conf missing expected directives"
        success_msg: "logind.conf contains all expected power action directives"

    - name: Assert logind.conf contains [Login] section
      ansible.builtin.assert:
        that: "'[Login]' in pm_verify_logind_text"
        fail_msg: "logind.conf missing [Login] section header"

    # ---- udev governor rule (desktop path) ----

    - name: Stat /etc/udev/rules.d/50-cpu-governor.rules
      ansible.builtin.stat:
        path: /etc/udev/rules.d/50-cpu-governor.rules
      register: pm_verify_udev_rule
      when: not pm_verify_is_laptop

    - name: Assert udev governor rule exists (desktop)
      ansible.builtin.assert:
        that:
          - pm_verify_udev_rule.stat.exists
          - pm_verify_udev_rule.stat.mode == '0644'
        fail_msg: "50-cpu-governor.rules missing or wrong permissions"
        success_msg: "udev governor rule deployed"
      when: not pm_verify_is_laptop

    - name: Read udev governor rule content
      ansible.builtin.slurp:
        src: /etc/udev/rules.d/50-cpu-governor.rules
      register: pm_verify_udev_content
      when:
        - not pm_verify_is_laptop
        - pm_verify_udev_rule.stat.exists | default(false)

    - name: Assert udev rule contains correct governor
      ansible.builtin.assert:
        that:
          - "'SUBSYSTEM==\"cpu\"' in (pm_verify_udev_content.content | b64decode)"
          - "'scaling_governor' in (pm_verify_udev_content.content | b64decode)"
          - "'schedutil' in (pm_verify_udev_content.content | b64decode)"
        fail_msg: "udev rule does not contain expected governor configuration"
        success_msg: "udev rule contains correct governor (schedutil)"
      when:
        - not pm_verify_is_laptop
        - pm_verify_udev_content is not skipped

    # ==== Audit Infrastructure Checks ====

    - name: Stat /usr/local/bin/power-audit.sh
      ansible.builtin.stat:
        path: /usr/local/bin/power-audit.sh
      register: pm_verify_audit_script

    - name: Assert power-audit.sh deployed and executable
      ansible.builtin.assert:
        that:
          - pm_verify_audit_script.stat.exists
          - pm_verify_audit_script.stat.mode == '0755'
          - pm_verify_audit_script.stat.pw_name == 'root'
        fail_msg: "power-audit.sh missing or wrong permissions"
        success_msg: "power-audit.sh deployed with mode 0755"

    - name: Read power-audit.sh content
      ansible.builtin.slurp:
        src: /usr/local/bin/power-audit.sh
      register: pm_verify_audit_content

    - name: Assert audit script contains expected checks
      ansible.builtin.assert:
        that:
          - "'#!/usr/bin/env bash' in (pm_verify_audit_content.content | b64decode)"
          - "'power-audit' in (pm_verify_audit_content.content | b64decode)"
          - "'scaling_governor' in (pm_verify_audit_content.content | b64decode)"
          - "'tlp-stat' in (pm_verify_audit_content.content | b64decode)"
        fail_msg: "power-audit.sh missing expected content"
        success_msg: "power-audit.sh contains expected audit checks"

    - name: Stat /etc/systemd/system/power-audit.service
      ansible.builtin.stat:
        path: /etc/systemd/system/power-audit.service
      register: pm_verify_audit_service

    - name: Assert power-audit.service unit deployed
      ansible.builtin.assert:
        that:
          - pm_verify_audit_service.stat.exists
          - pm_verify_audit_service.stat.mode == '0644'
        fail_msg: "power-audit.service unit missing"
        success_msg: "power-audit.service unit deployed"

    - name: Stat /etc/systemd/system/power-audit.timer
      ansible.builtin.stat:
        path: /etc/systemd/system/power-audit.timer
      register: pm_verify_audit_timer

    - name: Assert power-audit.timer unit deployed
      ansible.builtin.assert:
        that:
          - pm_verify_audit_timer.stat.exists
          - pm_verify_audit_timer.stat.mode == '0644'
        fail_msg: "power-audit.timer unit missing"
        success_msg: "power-audit.timer unit deployed"

    - name: Check power-audit.timer is enabled
      ansible.builtin.command: systemctl is-enabled power-audit.timer
      register: pm_verify_audit_timer_enabled
      changed_when: false
      failed_when: false

    - name: Assert power-audit.timer is enabled
      ansible.builtin.assert:
        that: pm_verify_audit_timer_enabled.stdout | trim == 'enabled'
        fail_msg: "power-audit.timer is not enabled (status: {{ pm_verify_audit_timer_enabled.stdout | trim }})"
        success_msg: "power-audit.timer is enabled"

    # ==== Conflicting Services Masked ====

    - name: Check power-profiles-daemon is masked or not found
      ansible.builtin.command: systemctl is-enabled power-profiles-daemon
      register: pm_verify_ppd_status
      changed_when: false
      failed_when: false

    - name: Assert power-profiles-daemon is masked or absent
      ansible.builtin.assert:
        that: pm_verify_ppd_status.stdout | trim in ['masked', 'not-found'] or pm_verify_ppd_status.rc != 0
        fail_msg: "power-profiles-daemon is not masked (status: {{ pm_verify_ppd_status.stdout | trim }})"
        success_msg: "power-profiles-daemon is masked or absent"

    - name: Check auto-cpufreq is masked or not found
      ansible.builtin.command: systemctl is-enabled auto-cpufreq
      register: pm_verify_autocpufreq_status
      changed_when: false
      failed_when: false

    - name: Assert auto-cpufreq is masked or absent
      ansible.builtin.assert:
        that: pm_verify_autocpufreq_status.stdout | trim in ['masked', 'not-found'] or pm_verify_autocpufreq_status.rc != 0
        fail_msg: "auto-cpufreq is not masked (status: {{ pm_verify_autocpufreq_status.stdout | trim }})"
        success_msg: "auto-cpufreq is masked or absent"

    # ==== Drift Detection State ====

    - name: Stat /var/lib/ansible-power-management
      ansible.builtin.stat:
        path: /var/lib/ansible-power-management
      register: pm_verify_drift_dir

    - name: Assert drift state directory exists with correct permissions
      ansible.builtin.assert:
        that:
          - pm_verify_drift_dir.stat.exists
          - pm_verify_drift_dir.stat.isdir
          - pm_verify_drift_dir.stat.mode == '0700'
          - pm_verify_drift_dir.stat.pw_name == 'root'
        fail_msg: "Drift state directory missing or wrong permissions"
        success_msg: "Drift state directory exists (mode 0700, root-owned)"

    - name: Stat drift state file
      ansible.builtin.stat:
        path: /var/lib/ansible-power-management/last_state.json
      register: pm_verify_drift_state

    - name: Assert drift state file exists with correct permissions
      ansible.builtin.assert:
        that:
          - pm_verify_drift_state.stat.exists
          - pm_verify_drift_state.stat.mode == '0600'
        fail_msg: "Drift state file missing or wrong mode"
        success_msg: "Drift state file exists (mode 0600)"

    - name: Read drift state file
      ansible.builtin.slurp:
        src: /var/lib/ansible-power-management/last_state.json
      register: pm_verify_drift_content

    - name: Assert drift state file is valid JSON with expected keys
      ansible.builtin.assert:
        that:
          - (pm_verify_drift_content.content | b64decode | from_json).governor is defined
          - (pm_verify_drift_content.content | b64decode | from_json).is_laptop is defined
          - (pm_verify_drift_content.content | b64decode | from_json).init_system is defined
          - (pm_verify_drift_content.content | b64decode | from_json).battery is defined
        fail_msg: "Drift state JSON missing expected keys"
        success_msg: "Drift state JSON contains required fields"

    # ==== CPU Governor (hardware-dependent, conditional) ====

    - name: Read current CPU governor
      ansible.builtin.slurp:
        src: /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
      register: pm_verify_governor
      failed_when: false
      when: pm_verify_cpufreq_available.stat.exists | default(false)

    - name: Assert governor is set (when cpufreq available)
      ansible.builtin.assert:
        that:
          - pm_verify_governor is succeeded
          - (pm_verify_governor.content | b64decode | trim) in ['schedutil', 'performance', 'powersave', 'ondemand', 'conservative']
        fail_msg: "CPU governor not set to a valid value"
        success_msg: "CPU governor: {{ pm_verify_governor.content | b64decode | trim }}"
      when:
        - pm_verify_cpufreq_available.stat.exists | default(false)
        - pm_verify_governor is succeeded

    # ==== Arch-specific: systemd-rfkill masked (laptop path only, informational) ====

    - name: Check systemd-rfkill masked (Arch laptop only)
      ansible.builtin.command: systemctl is-enabled systemd-rfkill.service
      register: pm_verify_rfkill_status
      changed_when: false
      failed_when: false
      when:
        - ansible_facts['os_family'] == 'Archlinux'
        - pm_verify_is_laptop

    - name: Assert systemd-rfkill masked (Arch laptop)
      ansible.builtin.assert:
        that: pm_verify_rfkill_status.stdout | trim in ['masked', 'not-found'] or pm_verify_rfkill_status.rc != 0
        fail_msg: "systemd-rfkill not masked on Arch laptop"
        success_msg: "systemd-rfkill is masked"
      when:
        - ansible_facts['os_family'] == 'Archlinux'
        - pm_verify_is_laptop

    # ==== Summary ====

    - name: Show verification summary
      ansible.builtin.debug:
        msg:
          - "All power_management verification checks passed."
          - "OS: {{ ansible_facts['os_family'] }}"
          - "Device: {{ 'laptop' if pm_verify_is_laptop else 'desktop' }}"
          - "cpufreq available: {{ pm_verify_cpufreq_available.stat.exists | default(false) }}"
          - "Configs: sleep.conf, logind.conf deployed with correct content"
          - "Udev rule: {{ 'deployed' if not pm_verify_is_laptop else 'skipped (laptop)' }}"
          - "Audit: script + service + timer deployed and enabled"
          - "Drift: state directory and file present with correct permissions"
          - "Conflicts: power-profiles-daemon + auto-cpufreq masked/absent"
```

### Verify design decisions

1. **No `vars_files` for defaults** -- Instead of loading `../../defaults/main.yml` to get
   default values, the verify hardcodes expected values from the defaults (e.g.,
   `HibernateMode=platform`, `HandleLidSwitch=suspend`, governor `schedutil`). This avoids
   path resolution issues across Docker and Vagrant and makes the verify self-documenting
   about what it expects.

2. **`systemctl is-enabled` instead of `service_facts`** -- `service_facts` does not report
   `.timer` units reliably (known Ansible issue #78107). Using `systemctl is-enabled` command
   directly is more reliable for timers.

3. **CPU governor check is conditional** on `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
   existing. This path does not exist in Docker containers.

4. **Config content verified** -- Not just existence. Specific directives and their default
   values are asserted (all 8 logind directives, HibernateMode, udev rule content).

5. **Drift state JSON validated** -- Checks that the JSON file is parseable and contains the
   expected top-level keys.

6. **Conflicting services checked via `systemctl is-enabled`** -- handles both "masked" and
   "not-found" (service never installed) cases.

---

## 8. Implementation Order

### Phase 1: Fix latent bug (required before testing works)

1. **Fix `_power_management_supported_os` reference in `install.yml`** -- Either:
   - (a) Rename the variable in `defaults/main.yml` to `_power_management_supported_os` (private
     convention with leading underscore) and update the reference, or
   - (b) Change `install.yml` line 13 to reference `power_management_supported_os` (matching defaults)

   Without this fix, `install.yml` will always skip the `include_tasks` because the undefined
   variable evaluates to empty.

2. **Fix `governor.yml` cpupower command failure in containers** -- Add
   `power_management_current_governor != 'unknown'` to the `when:` condition on the
   `cpupower frequency-set` task (line 39-42). This prevents converge failure in Docker
   where `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` is absent.

### Phase 2: Create shared playbooks

3. Create `molecule/shared/` directory
4. Create `molecule/shared/converge.yml` (as designed in section 3)
5. Create `molecule/shared/verify.yml` (as designed in section 7)

### Phase 3: Create Docker scenario

6. Create `molecule/docker/` directory
7. Create `molecule/docker/molecule.yml` (as designed in section 5)
8. Create `molecule/docker/prepare.yml` (as designed in section 5)
9. Run `molecule test -s docker` -- fix any issues

### Phase 4: Create Vagrant scenario

10. Create `molecule/vagrant/` directory
11. Create `molecule/vagrant/molecule.yml` (as designed in section 6)
12. Create `molecule/vagrant/prepare.yml` (as designed in section 6)
13. Run `molecule test -s vagrant` -- fix any issues

### Phase 5: Update default scenario

14. Update `molecule/default/molecule.yml` to point converge/verify to `../shared/`
15. Remove vault dependency from default scenario (role has no vault variables)
16. Delete the old `molecule/default/converge.yml` and `molecule/default/verify.yml`
    (replaced by shared/)

### Phase 6: Validation

17. Run `molecule test -s docker` -- full pass
18. Run `molecule test -s vagrant` -- full pass on both Arch and Ubuntu
19. Run `molecule test -s default` -- full pass (localhost)
20. Verify idempotence passes in all scenarios

---

## 9. Risks / Notes

### Hardware-dependent features untestable in CI

| Feature | Risk Level | Mitigation |
|---------|-----------|------------|
| CPU governor actually applied | Medium | Test file deployment (udev rule content); governor assertion is conditional |
| TLP managing real power subsystems | Low | TLP installs and service starts; actual hardware effects untestable |
| Battery charge thresholds | Low | Converge disables battery audit; thresholds only configured when variables are non-empty (empty by default) |
| Suspend/hibernate behavior | Low | Only config file deployment tested; actual power state changes untestable |
| udev rule fires on CPU hotplug | Low | File deployment tested; runtime behavior requires real hardware |
| logind lid-switch/power-key behavior | Low | Config content tested; actual D-Bus signal handling untestable |
| TLP backup/rollback (block/rescue) | Medium | Only exercised when template deployment fails; hard to trigger in tests |

### Bug: `_power_management_supported_os` is undefined

**Severity:** High -- silently skips all package installation.

The `install.yml` task references `_power_management_supported_os` (with leading underscore),
but `defaults/main.yml` defines `power_management_supported_os` (without leading underscore).
In Ansible, referencing an undefined variable in a `when:` condition with the `in` operator
against an undefined variable will cause an error or (with `DEFAULT_UNDEFINED_VAR_BEHAVIOR=false`)
evaluate the condition as falsy, skipping the task.

This means **no packages are currently being installed by the role via the install dispatcher**.
The existing default/ molecule tests may pass because they run on localhost where packages
are already installed.

**Must be fixed in Phase 1 before any molecule testing can validate package installation.**

### Idempotence considerations

- `cpupower frequency-set` with `changed_when: power_management_current_governor != power_management_cpu_governor`
  will report changed in containers where the governor reads as `unknown`. After fixing
  the bug (Phase 1 step 2), this task will be skipped entirely, resolving the idempotence issue.
- `drift_detection.yml` writes `last_state.json` on every run. If the governor or TLP status
  is slightly different between runs (e.g., `unknown` vs `unknown`), the file content won't
  change, so `ansible.builtin.copy` will be idempotent. This should be fine.
- TLP backup task uses `ansible_date_time.epoch` in the backup filename, which changes between
  runs. However, TLP tasks only run in laptop mode, which is skipped in the default converge.

### Docker image requirements

The `ghcr.io/textyre/bootstrap/arch-systemd:latest` image must include:
- systemd as PID 1
- pacman with synced database (prepare.yml does `update_cache`)
- No pre-installed TLP/cpupower (test should install them)

### Vagrant box considerations

- `generic/arch` box often has stale pacman keyring -- prepare.yml handles this
- `bento/ubuntu-24.04` may have `power-profiles-daemon` pre-installed -- the role masks it,
  and verify checks for masked status
- Both boxes should have cpufreq support if the KVM host exposes it (depends on libvirt
  CPU model configuration)

### Testing the laptop path

The default converge forces `desktop` mode. To test the laptop path (TLP installation,
config deployment, service enablement), a separate converge variant would be needed:

```yaml
- role: power_management
  vars:
    power_management_device_type: laptop
    power_management_assert_strict: false
    power_management_audit_battery: false
```

This is out of scope for this initial plan but could be added as an additional Docker
scenario (e.g., `molecule/docker-laptop/`) in a future iteration. The verify.yml already
has conditional checks that will activate when `pm_verify_is_laptop` is true.
