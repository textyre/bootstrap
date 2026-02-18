# timezone role — redesign implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the timezone role to its core responsibility: set system timezone and ensure tzdata is present, with package names sourced from the central registry.

**Architecture:** Remove the `install/` per-distro task dispatch pattern. Replace with a single package task driven by `packages_tzdata` from `group_vars/all/packages.yml`. Update meta to the five supported platforms. Keep verify/ unchanged.

**Tech Stack:** Ansible, `community.general.timezone` module, molecule (Arch Linux localhost driver)

**Design doc:** `docs/plans/2026-02-18-timezone-role-redesign-design.md`

---

### Task 1: Add `packages_tzdata` to central package registry

**Files:**
- Modify: `ansible/inventory/group_vars/all/packages.yml`

**Step 1: Add the tzdata section**

Find the end of `packages.yml` and append a new section after the last block:

```yaml
# ============================================================
#  timezone — роль roles/timezone
# ============================================================

# Пакет базы данных часовых поясов
# Ключ: ansible_facts['os_family'] | default('default')
packages_tzdata:
  Gentoo: "sys-libs/timezone-data"
  default: "tzdata"
```

**Step 2: Verify syntax**

Run on the remote VM:
```bash
ansible-playbook ansible/playbooks/site.yml --syntax-check
```
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/inventory/group_vars/all/packages.yml
git commit -m "feat(timezone): add packages_tzdata to central package registry"
```

---

### Task 2: Simplify role defaults

**Files:**
- Modify: `ansible/roles/timezone/defaults/main.yml`

**Step 1: Replace content**

Current content has `timezone_name: "Asia/Almaty"`. Replace with UTC fallback (real value lives in `system.yml`):

```yaml
---
# === Таймзона ===
# Имя таймзоны в формате tz database (timedatectl list-timezones)
# Реальное значение задаётся в group_vars/all/system.yml
timezone_name: "UTC"
```

**Step 2: Verify `system.yml` already has the real value**

Check that `ansible/inventory/group_vars/all/system.yml` contains:
```yaml
timezone_name: "Asia/Almaty"
```
It should already be there (confirmed in design phase). No change needed.

**Step 3: Commit**

```bash
git add ansible/roles/timezone/defaults/main.yml
git commit -m "feat(timezone): move timezone_name default to UTC, real value in system.yml"
```

---

### Task 3: Update meta — supported platforms

**Files:**
- Modify: `ansible/roles/timezone/meta/main.yml`

**Step 1: Replace platforms block**

Current platforms: ArchLinux, Debian, Ubuntu, EL, Alpine.
New platforms: ArchLinux, Fedora, Ubuntu, Void, Gentoo.

Replace the `galaxy_info` section:

```yaml
---
galaxy_info:
  role_name: timezone
  author: textyre
  description: >-
    Set system timezone. Supports Arch Linux, Fedora, Ubuntu, Void Linux, Gentoo.
    Installs tzdata via packages_tzdata when defined.
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Fedora
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: Void
      versions: [all]
    - name: Gentoo
      versions: [all]
  galaxy_tags: [system, timezone]
dependencies: []
```

**Step 2: Commit**

```bash
git add ansible/roles/timezone/meta/main.yml
git commit -m "feat(timezone): update supported platforms to Arch/Fedora/Ubuntu/Void/Gentoo"
```

---

### Task 4: Rewrite `tasks/main.yml` — replace install dispatch with package variable

**Files:**
- Modify: `ansible/roles/timezone/tasks/main.yml`
- Delete: `ansible/roles/timezone/tasks/install/` (entire directory)

**Step 1: Write updated `tasks/main.yml`**

```yaml
---
# === Таймзона ===
# Установка системной таймзоны
# Дистро-агностик, инит-агностик
# Действие → Проверка → Логирование

# ======================================================================
# ---- Установка tzdata ----
# ======================================================================

- name: Install tzdata
  ansible.builtin.package:
    name: "{{ packages_tzdata[ansible_facts['os_family']] | default(packages_tzdata['default']) }}"
    state: present
  when: packages_tzdata is defined
  tags: ['timezone']

# ======================================================================
# ---- Установка таймзоны ----
# ======================================================================

- name: Set timezone
  community.general.timezone:
    name: "{{ timezone_name }}"
  tags: ['timezone']

# ======================================================================
# ---- Проверка ----
# ======================================================================

- name: Verify timezone
  ansible.builtin.include_tasks:
    file: "verify/{{ 'systemd' if ansible_facts['service_mgr'] == 'systemd' else 'generic' }}.yml"
  tags: ['timezone']

# ======================================================================
# ---- Отчёт ----
# ======================================================================

- name: "Report: Set timezone"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_timezone_phases"
    _rpt_phase: "Set timezone"
    _rpt_detail: "{{ timezone_name }}"
  tags: ['timezone', 'report']

- name: "timezone — Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_timezone_phases"
    _rpt_title: "timezone"
  tags: ['timezone', 'report']
```

**Step 2: Delete the `install/` directory**

```bash
rm -rf ansible/roles/timezone/tasks/install/
```

**Step 3: Run syntax check**

```bash
ansible-playbook ansible/playbooks/site.yml --syntax-check
```
Expected: no errors

**Step 4: Commit**

```bash
git add ansible/roles/timezone/tasks/main.yml
git rm -r ansible/roles/timezone/tasks/install/
git commit -m "feat(timezone): replace install dispatch with packages_tzdata variable"
```

---

### Task 5: Update molecule converge — pass `packages_tzdata`

**Files:**
- Modify: `ansible/roles/timezone/molecule/default/converge.yml`

**Step 1: Add `packages_tzdata` to role vars**

The molecule test runs on Arch Linux localhost. `tzdata` is preinstalled on Arch (via glibc dependency), so this is an idempotency test — state: present will be a no-op.

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  pre_tasks:
    - name: Ensure we're running on Arch Linux
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] == 'Archlinux'
        fail_msg: "This test requires Arch Linux"

  roles:
    - role: timezone
      vars:
        timezone_name: "Asia/Almaty"
        packages_tzdata:
          default: "tzdata"
```

**Step 2: Run molecule**

On the remote VM:
```bash
cd ansible && molecule test -s default -- --role timezone
```
Expected: syntax → converge → verify all pass

**Step 3: Commit**

```bash
git add ansible/roles/timezone/molecule/default/converge.yml
git commit -m "test(timezone): pass packages_tzdata in molecule converge"
```

---

### Task 6: Lint

**Step 1: Run ansible-lint**

On the remote VM:
```bash
cd ansible && ansible-lint roles/timezone/
```
Expected: no violations

**Step 2: Fix any lint issues, commit if changed**

```bash
git add ansible/roles/timezone/
git commit -m "fix(timezone): address ansible-lint violations"
```

---

### Task 7: Full molecule run + final verification

**Step 1: Run full molecule test sequence**

On the remote VM:
```bash
cd ansible && molecule test -s default -- --role timezone
```
Expected sequence: syntax → converge → verify

**Step 2: Verify idempotency manually**

Run converge twice and confirm no changes on second run:
```bash
cd ansible && molecule converge -s default -- --role timezone
cd ansible && molecule converge -s default -- --role timezone
```
Expected: second run reports 0 changes

**Step 3: Final commit if anything was adjusted**

```bash
git add ansible/roles/timezone/
git commit -m "test(timezone): confirm idempotency"
```
