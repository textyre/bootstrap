# Reflector Role — SOLID Refactoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the monolithic `tasks/main.yml` (113 lines) into four SRP-focused `import_tasks` zones, add pacman hook, backup rotation, mirrorlist validation with rollback, and `RandomizedDelaySec` on the timer.

**Architecture:** `main.yml` becomes a slim orchestrator delegating to `install.yml`, `configure.yml`, `service.yml`, `update.yml`. The `update.yml` wraps the reflector run in a `block/rescue` to enable rollback on failure. A new static file `files/reflector-mirrorlist.hook` is deployed by `configure.yml` and fires when `pacman-mirrorlist` is upgraded. Backup rotation keeps the N newest files via `ansible.builtin.find` + `ansible.builtin.file`.

**Tech Stack:** Ansible 2.15+, `community.general.pacman`, systemd, Molecule (delegated/localhost driver). Lint via `task lint`. Tests via `task test-reflector` or `molecule test` in `ansible/roles/reflector/`. All remote runs on the Arch Linux VM.

**Design doc:** `docs/plans/2026-02-22-reflector-role-refactor-design.md`

---

## Task 1: Add three new defaults variables

**Files:**
- Modify: `ansible/roles/reflector/defaults/main.yml`

**Step 1: Append new variables at the end of the file**

In `ansible/roles/reflector/defaults/main.yml`, append after `reflector_proxy: ""`:

```yaml

# Backup rotation: how many timestamped backups to keep (0 = keep all)
reflector_backup_keep: 3

# Timer randomization: prevents thundering-herd on multi-machine deploys
reflector_timer_randomized_delay: "1h"

# Pacman hook: auto-update mirrorlist when pacman-mirrorlist package is upgraded
reflector_pacman_hook: true
```

**Step 2: Run lint**

```bash
task lint
```

Expected: clean — no errors from defaults file.

**Step 3: Commit**

```bash
git add ansible/roles/reflector/defaults/main.yml
git commit -m "feat(reflector): add backup_keep, timer_randomized_delay, pacman_hook defaults"
```

---

## Task 2: Create the pacman hook static file

**Files:**
- Create: `ansible/roles/reflector/files/reflector-mirrorlist.hook`

**Step 1: Create the hook file**

Create `ansible/roles/reflector/files/reflector-mirrorlist.hook` with this exact content:

```ini
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist

[Action]
Description = Updating mirrorlist via reflector after pacman-mirrorlist upgrade
When = PostTransaction
Depends = reflector
Exec = /usr/bin/reflector --config /etc/xdg/reflector/reflector.conf
```

The hook uses `--config` to read the Ansible-managed config — single source of truth, no argument duplication.

**Step 2: Run lint**

```bash
task lint
```

Expected: clean (Ansible lint ignores `.hook` files).

**Step 3: Commit**

```bash
git add ansible/roles/reflector/files/reflector-mirrorlist.hook
git commit -m "feat(reflector): add pacman hook for pacman-mirrorlist auto-update"
```

---

## Task 3: Create tasks/install.yml

**Files:**
- Create: `ansible/roles/reflector/tasks/install.yml`

**Step 1: Create the file**

Create `ansible/roles/reflector/tasks/install.yml`:

```yaml
---
- name: Install reflector package (latest version)
  community.general.pacman:
    name: reflector
    state: latest
  tags: ['install']
```

This is a direct extraction of the install task from `tasks/main.yml`. No logic changes.

**Step 2: Run lint**

```bash
task lint
```

Expected: clean.

**Step 3: Commit**

```bash
git add ansible/roles/reflector/tasks/install.yml
git commit -m "refactor(reflector): extract install.yml from main.yml"
```

---

## Task 4: Create tasks/configure.yml

**Files:**
- Create: `ansible/roles/reflector/tasks/configure.yml`

**Step 1: Create the file**

Create `ansible/roles/reflector/tasks/configure.yml`:

```yaml
---
- name: Deploy reflector config
  ansible.builtin.template:
    src: reflector.conf.j2
    dest: "{{ reflector_conf_path }}"
    owner: root
    group: root
    mode: '0644'
  notify: Reload systemd
  tags: ['configure']

- name: Ensure timer dropin dir exists
  ansible.builtin.file:
    path: /etc/systemd/system/reflector.timer.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  tags: ['configure']

- name: Set reflector timer schedule drop-in
  ansible.builtin.copy:
    dest: /etc/systemd/system/reflector.timer.d/override.conf
    content: |
      [Timer]
      OnCalendar={{ reflector_timer_schedule }}
      RandomizedDelaySec={{ reflector_timer_randomized_delay }}
    owner: root
    group: root
    mode: '0644'
  notify: Reload systemd
  tags: ['configure']

- name: Ensure /etc/pacman.d/hooks directory exists
  ansible.builtin.file:
    path: /etc/pacman.d/hooks
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: reflector_pacman_hook | bool
  tags: ['configure']

- name: Deploy pacman hook for mirrorlist auto-update
  ansible.builtin.copy:
    src: reflector-mirrorlist.hook
    dest: /etc/pacman.d/hooks/reflector-mirrorlist.hook
    owner: root
    group: root
    mode: '0644'
  when: reflector_pacman_hook | bool
  tags: ['configure']
```

Two changes vs. the extracted configure tasks:
1. `OnCalendar` line now also includes `RandomizedDelaySec={{ reflector_timer_randomized_delay }}`
2. Two new tasks at the bottom for the pacman hook

**Step 2: Run lint**

```bash
task lint
```

Expected: clean.

**Step 3: Commit**

```bash
git add ansible/roles/reflector/tasks/configure.yml
git commit -m "refactor(reflector): extract configure.yml, add RandomizedDelaySec and pacman hook"
```

---

## Task 5: Create tasks/service.yml

**Files:**
- Create: `ansible/roles/reflector/tasks/service.yml`

**Step 1: Create the file**

Create `ansible/roles/reflector/tasks/service.yml`:

```yaml
---
- name: Ensure reflector.timer is enabled and started
  ansible.builtin.systemd:
    name: reflector.timer
    enabled: true
    state: started
    daemon_reload: true
  tags: ['service']
```

Direct extraction. `yes` → `true` for YAML 1.2 compliance (ansible-lint may warn on `yes`).

**Step 2: Run lint**

```bash
task lint
```

Expected: clean.

**Step 3: Commit**

```bash
git add ansible/roles/reflector/tasks/service.yml
git commit -m "refactor(reflector): extract service.yml from main.yml"
```

---

## Task 6: Create tasks/update.yml (most complex)

**Files:**
- Create: `ansible/roles/reflector/tasks/update.yml`

**Step 1: Create the file**

Create `ansible/roles/reflector/tasks/update.yml`:

```yaml
---
- name: Update pacman cache
  community.general.pacman:
    update_cache: true
  tags: ['update']

- name: Stat current mirrorlist
  ansible.builtin.stat:
    path: "{{ reflector_mirrorlist_path }}"
  register: _reflector_stat
  tags: ['update']

- name: Read current mirrorlist (for change comparison)
  ansible.builtin.slurp:
    src: "{{ reflector_mirrorlist_path }}"
  register: _reflector_old_mirror
  when: _reflector_stat.stat.exists
  tags: ['update']

- name: Backup current mirrorlist BEFORE update
  ansible.builtin.copy:
    remote_src: true
    src: "{{ reflector_mirrorlist_path }}"
    dest: "{{ reflector_mirrorlist_path }}.bak.{{ ansible_facts['date_time']['iso8601_basic'] }}"
    mode: '0644'
  register: _reflector_backup_result
  when:
    - reflector_backup_mirrorlist | bool
    - _reflector_stat.stat.exists
  tags: ['update']

- name: Record backup path as fact
  ansible.builtin.set_fact:
    _reflector_latest_backup: "{{ _reflector_backup_result.dest }}"
  when: _reflector_backup_result is not skipped
  tags: ['update']

- name: Run reflector and validate mirrorlist
  tags: ['update']
  block:
    - name: Run reflector to update mirrorlist (with retries)
      ansible.builtin.command: >-
        reflector
        --country {{ reflector_countries }}
        --protocol {{ reflector_protocol }}
        --latest {{ reflector_latest }}
        --sort {{ reflector_sort }}
        --age {{ reflector_age }}
        --connection-timeout {{ reflector_connection_timeout }}
        --download-timeout {{ reflector_download_timeout }}
        --threads {{ reflector_threads }}
        --save {{ reflector_mirrorlist_path }}
      register: _reflector_run
      retries: "{{ reflector_retries }}"
      delay: "{{ reflector_retry_delay }}"
      until: _reflector_run.rc == 0
      changed_when: false
      failed_when: _reflector_run.rc != 0
      check_mode: false
      environment: "{{ {'http_proxy': reflector_proxy, 'https_proxy': reflector_proxy} if reflector_proxy | length > 0 else {} }}"

    - name: Read new mirrorlist
      ansible.builtin.slurp:
        src: "{{ reflector_mirrorlist_path }}"
      register: _reflector_new_mirror

    - name: Validate mirrorlist contains Server entries
      ansible.builtin.command:
        cmd: grep -c '^Server = ' {{ reflector_mirrorlist_path }}
      register: _reflector_server_count
      changed_when: false
      failed_when: _reflector_server_count.stdout | int < 1

    - name: Find old mirrorlist backups for rotation
      ansible.builtin.find:
        paths: "{{ reflector_mirrorlist_path | dirname }}"
        patterns: "mirrorlist.bak.*"
      register: _reflector_backups
      when:
        - reflector_backup_mirrorlist | bool
        - reflector_backup_keep | int > 0

    - name: Remove oldest backups, keep N newest
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ (_reflector_backups.files | sort(attribute='mtime'))[: -reflector_backup_keep | int] }}"
      when:
        - reflector_backup_mirrorlist | bool
        - reflector_backup_keep | int > 0
        - _reflector_backups.matched > reflector_backup_keep | int

    - name: Determine if mirrorlist changed
      ansible.builtin.set_fact:
        _reflector_mirrorlist_changed: >-
          {{ (_reflector_old_mirror.content | default('')) != (_reflector_new_mirror.content | default('')) }}

    - name: Report reflector result
      ansible.builtin.debug:
        msg: >-
          Reflector completed. Mirrorlist changed: {{ _reflector_mirrorlist_changed }}.
          Servers in mirrorlist: {{ _reflector_server_count.stdout }}.
      changed_when: _reflector_mirrorlist_changed | bool

  rescue:
    - name: Restore mirrorlist from backup
      ansible.builtin.copy:
        remote_src: true
        src: "{{ _reflector_latest_backup }}"
        dest: "{{ reflector_mirrorlist_path }}"
        mode: '0644'
      when: _reflector_latest_backup is defined

    - name: Fail with descriptive message
      ansible.builtin.fail:
        msg: >-
          reflector failed or produced an invalid mirrorlist.
          {% if _reflector_latest_backup is defined %}
          Restored from {{ _reflector_latest_backup }}.
          {% else %}
          No backup was available — mirrorlist may be empty or missing.
          {% endif %}
```

Key changes vs. original `tasks/main.yml`:
- `ignore_errors: true` on slurp replaced by `stat` guard
- `update_cache` moved to top (before backup, so we have a fresh cache before running reflector)
- Backup path stored as fact for rescue access
- `block/rescue` wraps run → validate → cleanup → diff
- Server count validation: `grep -c '^Server = '` ≥ 1
- Backup cleanup via `find` + `file: absent` on oldest entries
- Rollback in `rescue`: copy latest backup back + `fail`

**Step 2: Run lint**

```bash
task lint
```

Expected: clean. If lint warns on `loop` slice syntax, verify the exact Jinja2 slice expression is accepted — it should be fine with Ansible 2.15+.

**Step 3: Commit**

```bash
git add ansible/roles/reflector/tasks/update.yml
git commit -m "refactor(reflector): extract update.yml with block/rescue, validation, backup rotation"
```

---

## Task 7: Replace tasks/main.yml with slim orchestrator

**Files:**
- Modify: `ansible/roles/reflector/tasks/main.yml`

**Step 1: Replace the entire file**

Replace `ansible/roles/reflector/tasks/main.yml` with:

```yaml
---
- name: Ensure host is Arch Linux
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] is defined
      - ansible_facts['os_family'] == 'Archlinux'
    fail_msg: "This role supports Arch Linux only"

- name: Install reflector
  ansible.builtin.import_tasks: install.yml

- name: Configure reflector
  ansible.builtin.import_tasks: configure.yml

- name: Enable reflector timer
  ansible.builtin.import_tasks: service.yml

- name: Update mirrorlist
  ansible.builtin.import_tasks: update.yml
```

Note: `import_tasks` (static) is used instead of `include_tasks` (dynamic) because tags need to pass through to child tasks and there are no conditional includes. Tags in child task files propagate automatically with `import_tasks`.

**Step 2: Run lint**

```bash
task lint
```

Expected: clean.

**Step 3: Syntax check**

```bash
cd ansible && ansible-playbook --syntax-check playbooks/workstation.yml
```

Expected: no syntax errors.

**Step 4: Commit**

```bash
git add ansible/roles/reflector/tasks/main.yml
git commit -m "refactor(reflector): replace monolithic main.yml with slim import_tasks orchestrator"
```

---

## Task 8: Update molecule/default/verify.yml with new checks

**Files:**
- Modify: `ansible/roles/reflector/molecule/default/verify.yml`

**Step 1: Add five new checks after the existing "Show test results" task**

Insert before the final `ansible.builtin.debug` "Show test results" task:

```yaml
    - name: Check that pacman hooks directory exists
      ansible.builtin.stat:
        path: /etc/pacman.d/hooks
      register: _reflector_hooks_dir
      failed_when: not _reflector_hooks_dir.stat.exists

    - name: Check that pacman hook file exists
      ansible.builtin.stat:
        path: /etc/pacman.d/hooks/reflector-mirrorlist.hook
      register: _reflector_hook
      failed_when: not _reflector_hook.stat.exists

    - name: Validate hook file content references pacman-mirrorlist and --config
      ansible.builtin.slurp:
        src: /etc/pacman.d/hooks/reflector-mirrorlist.hook
      register: _reflector_hook_content
      failed_when: >
        'pacman-mirrorlist' not in (_reflector_hook_content.content | b64decode) or
        '--config' not in (_reflector_hook_content.content | b64decode)

    - name: Validate timer drop-in contains RandomizedDelaySec
      ansible.builtin.slurp:
        src: /etc/systemd/system/reflector.timer.d/override.conf
      register: _reflector_dropin_content
      failed_when: >
        'RandomizedDelaySec' not in (_reflector_dropin_content.content | b64decode)

    - name: Count mirrorlist backup files
      ansible.builtin.find:
        paths: /etc/pacman.d
        patterns: "mirrorlist.bak.*"
      register: _reflector_verify_backups

    - name: Validate backup count does not exceed reflector_backup_keep
      ansible.builtin.assert:
        that:
          - _reflector_verify_backups.matched <= reflector_backup_keep | int
        fail_msg: >
          Found {{ _reflector_verify_backups.matched }} backup files,
          expected <= {{ reflector_backup_keep }}

    - name: Validate mirrorlist contains at least 3 Server entries
      ansible.builtin.command: grep -c '^Server = ' /etc/pacman.d/mirrorlist
      register: _reflector_verify_server_count
      changed_when: false
      failed_when: _reflector_verify_server_count.stdout | int < 3
```

Also update the final debug "Show test results" to include the new checks:

```yaml
    - name: Show test results
      ansible.builtin.debug:
        msg:
          - "✅ All checks passed!"
          - "✓ reflector package installed"
          - "✓ reflector.conf exists and valid"
          - "✓ timer override configured with RandomizedDelaySec"
          - "✓ reflector.timer enabled and active"
          - "✓ mirrorlist updated with {{ _reflector_verify_server_count.stdout }} servers (>= 3)"
          - "✓ pacman hook deployed at /etc/pacman.d/hooks/reflector-mirrorlist.hook"
          - "✓ backup count within limit: {{ _reflector_verify_backups.matched }} <= {{ reflector_backup_keep }}"
```

**Step 2: Run lint**

```bash
task lint
```

Expected: clean.

**Step 3: Commit**

```bash
git add ansible/roles/reflector/molecule/default/verify.yml
git commit -m "test(reflector): add verify checks for hook, RandomizedDelaySec, backup count, server count"
```

---

## Task 9: Final integration — run lint + molecule

**Step 1: Full lint run**

```bash
task lint
```

Expected: no warnings or errors from any reflector role file.

**Step 2: Run molecule test**

On the remote VM (create a snapshot first — molecule modifies the live mirrorlist):

```bash
cd ansible/roles/reflector && molecule test
```

Expected sequence:
- `syntax` — passes
- `converge` — role applies without errors; all tasks idempotent on second run
- `verify` — all 12 checks pass (7 existing + 5 new)

If `verify` fails on backup count check: the initial run creates 1 backup, `reflector_backup_keep: 3` allows up to 3, so count (1) ≤ keep (3) — should pass.

If server count check fails (< 3): KZ mirrors may be sparse — lower threshold to 1, or add more countries to `reflector_countries` in test vars.

**Step 3: Verify idempotency**

Run molecule converge a second time and check there are no `changed` tasks except the intentional "Report reflector result" debug task (which is `changed_when: mirrorlist_changed`).

```bash
molecule converge 2>&1 | grep -E "changed=|failed="
```

Expected: `changed=0` or `changed=1` (only if mirrorlist actually changed), `failed=0`.

**Step 4: Final commit (if any fixups needed)**

```bash
git add -p  # stage only intentional changes
git commit -m "fix(reflector): post-molecule fixups"
```

---

## Summary of all changed files

| File | Action |
|------|--------|
| `ansible/roles/reflector/defaults/main.yml` | Modified — 3 new vars |
| `ansible/roles/reflector/files/reflector-mirrorlist.hook` | Created |
| `ansible/roles/reflector/tasks/main.yml` | Replaced — slim orchestrator |
| `ansible/roles/reflector/tasks/install.yml` | Created |
| `ansible/roles/reflector/tasks/configure.yml` | Created |
| `ansible/roles/reflector/tasks/service.yml` | Created |
| `ansible/roles/reflector/tasks/update.yml` | Created |
| `ansible/roles/reflector/molecule/default/verify.yml` | Modified — 5 new checks |
