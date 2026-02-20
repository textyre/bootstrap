# NTP Role Hardening — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden the `ntp` Ansible role by adding input validation, `ntp_enabled` guard, directory creation, `ntp_pools`/`ntp_allow`/`ntsdumpdir` support, extracted verify tasks, granular `ntp:state` tag, and stronger molecule tests with internet pre-condition and NTS verification.

**Architecture:** Pattern alignment with `keymap` role (validate → install → config → verify → report). New shared utility `common/tasks/check_internet.yml` used by both role verify and molecule verify via `include_role`. TDD: write failing molecule assertions first, then implement role changes to make them pass.

**Tech Stack:** Ansible 2.15+, chrony 4.0+ (Arch Linux), molecule/podman, chronyc CLI

**Design doc:** `docs/plans/2026-02-20-ntp-role-hardening-design.md`

---

### Task 1: Create `common/tasks/check_internet.yml`

**Files:**
- Create: `ansible/roles/common/tasks/check_internet.yml`

**Step 1: Create the file**

```yaml
---
# === Проверка интернет-соединения ===
# Общая утилита для ролей, требующих внешний сетевой доступ
# Параметры:
#   _check_internet_host     — хост для проверки (обязательный)
#   _check_internet_port     — порт для проверки (обязательный)
#   _check_internet_timeout  — таймаут в секундах (по умолчанию: 5)

- name: "Check internet connectivity ({{ _check_internet_host }}:{{ _check_internet_port }})"
  ansible.builtin.wait_for:
    host: "{{ _check_internet_host }}"
    port: "{{ _check_internet_port }}"
    timeout: "{{ _check_internet_timeout | default(5) }}"
  register: _common_internet_check
  failed_when: false

- name: Fail if internet is unavailable
  ansible.builtin.fail:
    msg: >-
      Internet connectivity required but unavailable.
      Cannot reach {{ _check_internet_host }}:{{ _check_internet_port }}.
      Fix network access before running this role.
  when: _common_internet_check is failed
```

**Step 2: Commit**

```bash
git add ansible/roles/common/tasks/check_internet.yml
git commit -m "feat(common): add check_internet shared utility task"
```

---

### Task 2: Extend `molecule/default/verify.yml` — write failing tests first (TDD)

**Files:**
- Modify: `ansible/roles/ntp/molecule/default/verify.yml`

**Step 1: Replace file content with extended verify**

Full replacement — add internet pre-check, directory checks, ntsdumpdir check, synced source check, NTS check. Keep all existing assertions unchanged.

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  tasks:

    # ---- Pre-condition: internet access ----

    - name: Check internet connectivity (NTP requires external access)
      ansible.builtin.include_role:
        name: common
        tasks_from: check_internet.yml
      vars:
        _check_internet_host: "time.cloudflare.com"
        _check_internet_port: 123

    # ---- chrony installed ----

    - name: Check chrony is installed
      ansible.builtin.command: command -v chronyd
      register: _verify_chrony
      changed_when: false
      failed_when: _verify_chrony.rc != 0

    # ---- service running ----

    - name: Check chronyd service is running (systemd)
      ansible.builtin.service_facts:
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert chronyd is active (systemd)
      ansible.builtin.assert:
        that:
          - "'chronyd.service' in ansible_facts.services"
          - "ansible_facts.services['chronyd.service'].state == 'running'"
        fail_msg: "chronyd is not running"
      when: ansible_facts['service_mgr'] == 'systemd'

    # ---- functional ----

    - name: Verify chrony is functional
      ansible.builtin.command: chronyc tracking
      register: _verify_ntp_tracking
      changed_when: false
      failed_when: _verify_ntp_tracking.rc != 0

    - name: Assert chrony daemon responds correctly
      ansible.builtin.assert:
        that:
          - "'Stratum' in _verify_ntp_tracking.stdout"
          - "'System time' in _verify_ntp_tracking.stdout"
        fail_msg: "chronyc tracking output invalid"

    - name: Verify chrony has NTP sources
      ansible.builtin.command: chronyc sources
      register: _verify_ntp_sources
      changed_when: false

    - name: Assert chrony has at least one source
      ansible.builtin.assert:
        that:
          - _verify_ntp_sources.stdout_lines | length > 2
        fail_msg: "chrony has no NTP sources configured"

    # ---- actual sync (requires internet) ----

    - name: Verify chrony has a synced source
      ansible.builtin.command: chronyc -n sources
      register: _verify_ntp_synced
      changed_when: false

    - name: Assert at least one source is synced (^* marker)
      ansible.builtin.assert:
        that:
          - _verify_ntp_synced.stdout_lines | select('match', '^\^\*') | list | length > 0
        fail_msg: >-
          No synchronized NTP source (no '^*' marker in chronyc -n sources).
          Chrony is running but not synced — internet connectivity may be missing.

    # ---- NTS authentication ----

    - name: Verify NTS sources are active
      ansible.builtin.command: chronyc ntssources
      register: _verify_nts_sources
      changed_when: false

    - name: Assert at least one NTS source is present
      ansible.builtin.assert:
        that:
          - _verify_nts_sources.stdout_lines | length > 1
        fail_msg: >-
          No NTS sources found (chronyc ntssources returned no entries).
          Check NTS server reachability and NTS handshake logs.

    # ---- config content ----

    - name: Verify chrony.conf is deployed by Ansible
      ansible.builtin.stat:
        path: /etc/chrony.conf
      register: _verify_chrony_conf

    - name: Assert chrony.conf exists and is a regular file
      ansible.builtin.assert:
        that:
          - _verify_chrony_conf.stat.exists
          - _verify_chrony_conf.stat.isreg
        fail_msg: "/etc/chrony.conf is missing"

    - name: Read chrony.conf content
      ansible.builtin.slurp:
        src: /etc/chrony.conf
      register: _verify_chrony_conf_content

    - name: Decode chrony.conf content
      ansible.builtin.set_fact:
        _verify_chrony_conf_text: "{{ _verify_chrony_conf_content.content | b64decode }}"

    - name: Assert NTS flag present in at least one server line
      ansible.builtin.assert:
        that:
          - "'nts' in _verify_chrony_conf_text"
        fail_msg: "No NTS servers found in /etc/chrony.conf"

    - name: Assert minsources directive present
      ansible.builtin.assert:
        that:
          - "'minsources' in _verify_chrony_conf_text"
        fail_msg: "minsources directive missing from /etc/chrony.conf"

    - name: Assert driftfile directive present
      ansible.builtin.assert:
        that:
          - "'driftfile' in _verify_chrony_conf_text"
        fail_msg: "driftfile directive missing from /etc/chrony.conf"

    - name: Assert dumpdir directive present
      ansible.builtin.assert:
        that:
          - "'dumpdir' in _verify_chrony_conf_text"
        fail_msg: "dumpdir directive missing from /etc/chrony.conf"

    - name: Assert ntsdumpdir directive present
      ansible.builtin.assert:
        that:
          - "'ntsdumpdir' in _verify_chrony_conf_text"
        fail_msg: "ntsdumpdir directive missing from /etc/chrony.conf"

    - name: Assert log tracking directive present
      ansible.builtin.assert:
        that:
          - "'log measurements statistics tracking' in _verify_chrony_conf_text"
        fail_msg: "log tracking directive missing from /etc/chrony.conf"

    # ---- directories ----

    - name: Check ntp_logdir exists
      ansible.builtin.stat:
        path: /var/log/chrony
      register: _verify_logdir

    - name: Assert ntp_logdir exists with correct ownership
      ansible.builtin.assert:
        that:
          - _verify_logdir.stat.exists
          - _verify_logdir.stat.isdir
          - _verify_logdir.stat.pw_name == 'chrony'
        fail_msg: "/var/log/chrony does not exist or is not owned by chrony"

    - name: Check ntp_ntsdumpdir exists
      ansible.builtin.stat:
        path: /var/lib/chrony/nts-data
      register: _verify_ntsdumpdir

    - name: Assert ntp_ntsdumpdir exists with correct ownership
      ansible.builtin.assert:
        that:
          - _verify_ntsdumpdir.stat.exists
          - _verify_ntsdumpdir.stat.isdir
          - _verify_ntsdumpdir.stat.pw_name == 'chrony'
        fail_msg: "/var/lib/chrony/nts-data does not exist or is not owned by chrony"

    - name: Show result
      ansible.builtin.debug:
        msg: "NTP check passed: chrony installed, running, synced, NTS active, directories correct"
```

**Step 2: Run molecule converge to set up container with current role**

Use `/ansible` skill:
```
molecule converge -s default -- --limit ntp
```
(or run via Taskfile if configured)

**Step 3: Run molecule verify — expect FAILURES on new assertions**

```
molecule verify -s default
```

Expected failures:
- `ntsdumpdir directive missing` — not in template yet
- `/var/log/chrony does not exist` — no dir creation task yet
- `/var/lib/chrony/nts-data does not exist` — no dir creation task yet
- NTS assertions may fail until chrony restarts with new config

**Step 4: Commit the failing tests**

```bash
git add ansible/roles/ntp/molecule/default/verify.yml
git commit -m "test(ntp): add internet check, dir existence, ntsdumpdir, NTS assertions"
```

---

### Task 3: Add new variables to `defaults/main.yml`

**Files:**
- Modify: `ansible/roles/ntp/defaults/main.yml`

**Step 1: Append new variables after `ntp_log_tracking`**

```yaml
# Pool-type NTP sources (pool directive — DNS round-robin with auto-rotation)
# Distinct from server: pool = multiple servers behind one hostname
# Example: [{host: "pool.ntp.org", iburst: true, maxsources: 4}]
ntp_pools: []

# ACL для NTP server mode (allow directive)
# Пустой список = только клиент, не раздаёт время
# Example: ["192.168.1.0/24", "10.0.0.0/8"]
ntp_allow: []

# NTS cookie cache directory (ускоряет повторное NTS-рукопожатие после перезапуска)
# chrony сохраняет NTS session cookies, при рестарте пропускает полный TLS handshake
ntp_ntsdumpdir: "/var/lib/chrony/nts-data"
```

**Step 2: No commit yet — continue to next task**

---

### Task 4: Update `templates/chrony.conf.j2`

**Files:**
- Modify: `ansible/roles/ntp/templates/chrony.conf.j2`

**Step 1: Replace file with updated template**

```jinja2
# Managed by Ansible — do not edit manually
# Role: ntp | Template: chrony.conf.j2

{% for server in ntp_servers %}
server {{ server.host }}{% if server.iburst | default(true) %} iburst{% endif %}{% if server.nts | default(false) %} nts{% endif %}

{% endfor %}
{% for pool in ntp_pools %}
pool {{ pool.host }}{% if pool.iburst | default(true) %} iburst{% endif %}{% if pool.maxsources is defined %} maxsources {{ pool.maxsources }}{% endif %}

{% endfor %}
# Clock stability
driftfile {{ ntp_driftfile }}
{% if ntp_dumpdir %}
dumpdir {{ ntp_dumpdir }}
{% endif %}
{% if ntp_ntsdumpdir %}
ntsdumpdir {{ ntp_ntsdumpdir }}
{% endif %}
makestep {{ ntp_makestep_threshold }} {{ ntp_makestep_limit }}
minsources {{ ntp_minsources }}

{% if ntp_rtcsync %}
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

**Step 2: Commit defaults + template together**

```bash
git add ansible/roles/ntp/defaults/main.yml ansible/roles/ntp/templates/chrony.conf.j2
git commit -m "feat(ntp): add ntp_pools, ntp_allow, ntp_ntsdumpdir variables and template"
```

---

### Task 5: Create `tasks/validate.yml`

**Files:**
- Create: `ansible/roles/ntp/tasks/validate.yml`

**Step 1: Create the file**

```yaml
---
# === NTP — валидация входных переменных ===
# Вызывается в начале main.yml до любых действий

- name: Assert at least one NTP source is configured
  ansible.builtin.assert:
    that:
      - (ntp_servers | default([]) | length) + (ntp_pools | default([]) | length) > 0
    fail_msg: >-
      At least one NTP source is required.
      Set ntp_servers (server directives) or ntp_pools (pool directives).
      Both are currently empty.
  tags: ['ntp']

- name: Assert ntp_minsources is a positive integer not exceeding source count
  ansible.builtin.assert:
    that:
      - ntp_minsources | int >= 1
      - ntp_minsources | int <= (ntp_servers | default([]) | length) + (ntp_pools | default([]) | length)
    fail_msg: >-
      ntp_minsources must be >= 1 and <= total number of sources.
      Current value: {{ ntp_minsources }}.
      Total sources configured: {{ (ntp_servers | default([]) | length) + (ntp_pools | default([]) | length) }}.
  tags: ['ntp']

- name: Assert ntp_makestep_threshold is positive
  ansible.builtin.assert:
    that:
      - ntp_makestep_threshold | float > 0
    fail_msg: >-
      ntp_makestep_threshold must be > 0 (seconds before chrony steps the clock).
      Current value: {{ ntp_makestep_threshold }}.
  tags: ['ntp']

- name: Assert ntp_makestep_limit is an integer >= -1
  ansible.builtin.assert:
    that:
      - ntp_makestep_limit | int >= -1
    fail_msg: >-
      ntp_makestep_limit must be >= -1 (-1 means unlimited clock steps on startup).
      Current value: {{ ntp_makestep_limit }}.
  tags: ['ntp']
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp/tasks/validate.yml
git commit -m "feat(ntp): add input validation in tasks/validate.yml"
```

---

### Task 6: Create `tasks/verify.yml`

**Files:**
- Create: `ansible/roles/ntp/tasks/verify.yml`

**Step 1: Create the file** — contains extracted verify tasks from `main.yml` plus new synced-source check and internet check.

```yaml
---
# === NTP — верификация после конфигурации ===
# Извлечено из main.yml; вызывается через include_tasks

# ---- Pre-condition: internet ----

- name: Check internet connectivity (NTP requires external access)
  ansible.builtin.include_role:
    name: common
    tasks_from: check_internet.yml
  vars:
    _check_internet_host: "time.cloudflare.com"
    _check_internet_port: 123
  tags: ['ntp']

# ---- Functional checks ----

- name: Verify chronyd is running
  ansible.builtin.command: chronyc tracking
  register: _ntp_check
  changed_when: false
  failed_when: _ntp_check.rc != 0
  tags: ['ntp']

- name: Assert chrony daemon is functional
  ansible.builtin.assert:
    that:
      - "'Stratum' in _ntp_check.stdout"
      - "'System time' in _ntp_check.stdout"
    fail_msg: "chronyc tracking output invalid — chrony may not be configured correctly"
    quiet: true
  tags: ['ntp']

- name: Check chrony has NTP sources
  ansible.builtin.command: chronyc sources
  register: _ntp_sources
  changed_when: false
  tags: ['ntp']

- name: Assert chrony has at least one source configured
  ansible.builtin.assert:
    that:
      - _ntp_sources.stdout_lines | length > 2
    fail_msg: "chrony has no NTP sources configured"
    quiet: true
  tags: ['ntp']

- name: Check chrony has a synced source
  ansible.builtin.command: chronyc -n sources
  register: _ntp_synced
  changed_when: false
  tags: ['ntp']

- name: Assert at least one source is synced (^* marker)
  ansible.builtin.assert:
    that:
      - _ntp_synced.stdout_lines | select('match', '^\^\*') | list | length > 0
    fail_msg: >-
      No synchronized NTP source (no '^*' marker in chronyc -n sources).
      Chrony is running but not synced — check internet connectivity and NTP server reachability.
    quiet: true
  tags: ['ntp']
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp/tasks/verify.yml
git commit -m "feat(ntp): extract verify tasks to tasks/verify.yml, add synced-source check"
```

---

### Task 7: Rewrite `tasks/main.yml`

**Files:**
- Modify: `ansible/roles/ntp/tasks/main.yml`

**Step 1: Replace file with refactored version**

Key changes vs. current:
- All tasks inside `block: when: ntp_enabled | bool`
- `include_tasks: validate.yml` at top
- Directory creation task (before config)
- `ntp:state` tag added to service task
- Inline verify tasks removed → `include_tasks: verify.yml`

```yaml
---
# === NTP — синхронизация времени ===
# chrony как универсальный NTP-демон (все дистро, все init-системы)
# validate → Установка → Конфигурация → Директории → Запуск → Проверка → Логирование

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
    # ---- Установка ----
    # ======================================================================

    - name: Install NTP daemon (chrony)
      ansible.builtin.package:
        name: "{{ _ntp_package[ansible_facts['os_family']] | default('chrony') }}"
        state: present
      tags: ['ntp']

    # ======================================================================
    # ---- Отключение конфликтующих демонов ----
    # ======================================================================

    - name: Disable conflicting time sync daemons
      ansible.builtin.include_tasks: "{{ item }}"
      with_first_found:
        - files:
            - "disable_{{ ansible_facts['service_mgr'] }}.yml"
          skip: true
      tags: ['ntp']

    # ======================================================================
    # ---- Директории ----
    # ======================================================================

    - name: Ensure chrony directories exist
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: directory
        owner: chrony
        group: chrony
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
        _rpt_detail: "chrony ({{ _ntp_service[ansible_facts['service_mgr']] | default('chronyd') }})"
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

**Step 2: Run molecule test — all assertions must pass**

Use `/ansible` skill:
```
molecule test -s default
```

Expected: all verify assertions GREEN. If failures:
- `ntsdumpdir missing` → check template Task 4
- `directory ownership` → check if `chrony` user exists in container (may need `pre_tasks` in converge if testing in minimal container)
- `^* synced source` → wait for chrony to sync (may take 30–60s after start; add `wait_for` in verify or increase molecule timeout)
- `chronyc ntssources > 1` → chrony NTS handshake may need extra seconds after start

**Step 3: Commit**

```bash
git add ansible/roles/ntp/tasks/main.yml
git commit -m "feat(ntp): add ntp_enabled guard, validate, dirs, verify extraction, ntp:state tag"
```

---

### Task 8: Update `README.md`

**Files:**
- Modify: `ansible/roles/ntp/README.md`

**Step 1: Update the Variables table** — add three new rows after `ntp_log_tracking`:

```markdown
| `ntp_pools` | `[]` | Pool-type sources (`pool` directive). Objects: `{host, iburst, maxsources}` |
| `ntp_allow` | `[]` | ACL for NTP server mode. Empty = client-only. Example: `["192.168.1.0/24"]` |
| `ntp_ntsdumpdir` | `/var/lib/chrony/nts-data` | NTS cookie cache — speeds up NTS re-handshake after restart |
```

**Step 2: Update the Tags section**:

```markdown
## Tags

`ntp`, `ntp:state` (service enable/start only), `ntp,report`

Use `--tags ntp:state` to restart chronyd without re-applying full configuration.
```

**Step 3: Commit**

```bash
git add ansible/roles/ntp/README.md
git commit -m "docs(ntp): update README with new variables and tags"
```

---

### Task 9: Final molecule run + ansible-lint

**Step 1: Full molecule test**

Use `/ansible` skill:
```
molecule test -s default
```

Expected output: all tasks green, verify assertions green.

**Step 2: Run ansible-lint**

```
ansible-lint ansible/roles/ntp/
```

Fix any lint warnings before final commit.

**Step 3: If lint fixes needed, commit them**

```bash
git add ansible/roles/ntp/
git commit -m "fix(ntp): address ansible-lint warnings"
```

---

## Potential Issues & Solutions

| Issue | Cause | Fix |
|-------|-------|-----|
| `chrony` user missing in molecule container | Minimal container, user not created by package | Ensure `molecule converge` installs chrony package before dir creation runs — already ordered correctly |
| `^*` not appearing after start | Chrony needs 30–60s to elect a source | Add `ansible.builtin.wait_for` in verify.yml before synced-source assert: `wait_for: timeout: 60 delay: 5` |
| `chronyc ntssources` command not found | chrony < 4.0 | Arch Linux ships chrony 4.5+ — should not be an issue |
| `include_tasks` + `block` when condition | Known Ansible behavior: `when` on block propagates to all tasks including `include_tasks` | Confirmed correct — no issue |
| `ntp_allow | length > 0` in template | Jinja2 on empty list | Correct — empty list has length 0, condition false, `allow` lines not rendered |
