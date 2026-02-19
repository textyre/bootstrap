# keymap role improvement — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Довести роль `keymap` до production-grade: добавить validate-фазу, handler для немедленного применения, verify для openrc/runit, улучшить systemd verify, раскомментировать font-переменные, убрать Arch-ограничение из Molecule.

**Architecture:** validate → apply (с notify handler) → verify → report. Handler единый с разводкой по init через `when`. Паттерн `with_first_found + skip` сохраняется для диспатча.

**Tech Stack:** Ansible 2.15+, Molecule (ansible verifier), common role reporter.

**Design doc:** `docs/plans/2026-02-19-keymap-role-improvement-design.md`

**Role path:** `ansible/roles/keymap/`

---

### Task 1: Uncomment font variables in defaults/main.yml

**Files:**
- Modify: `ansible/roles/keymap/defaults/main.yml`

**Step 1: Replace defaults/main.yml**

```yaml
---
# === Console keymap (TTY) ===

keymap_console: "us"

# Optional: console font (e.g. "ter-v16n", "lat2-16")
keymap_console_font: ""

# Optional: font map (e.g. "8859-2")
keymap_console_font_map: ""

# Optional: unicode map file
keymap_console_font_unimap: ""
```

**Step 2: Verify syntax**

```bash
task lint
```

Expected: no errors on keymap role.

**Step 3: Commit**

```bash
git add ansible/roles/keymap/defaults/main.yml
git commit -m "chore(keymap): expose font variables in defaults"
```

---

### Task 2: Create validate/main.yml + update tasks/main.yml

**Files:**
- Create: `ansible/roles/keymap/tasks/validate/main.yml`
- Modify: `ansible/roles/keymap/tasks/main.yml`

**Step 1: Create the validate directory and file**

Create `ansible/roles/keymap/tasks/validate/main.yml`:

```yaml
---
# === Validate keymap configuration ===

- name: Assert keymap_console is defined and non-empty
  ansible.builtin.assert:
    that:
      - keymap_console is defined
      - keymap_console | length > 0
    fail_msg: >-
      keymap_console must be set to a valid keymap name (e.g. 'us', 'ru').
      Current value: '{{ keymap_console | default("") }}'
  tags: ['keymap']
```

**Step 2: Add validate include to tasks/main.yml**

Current `tasks/main.yml` starts with the Configure task. Add validate before it.

Replace the content of `ansible/roles/keymap/tasks/main.yml` with:

```yaml
---
# === Console keymap — диспетчер по init-системе ===
# validate → Настройка → Проверка → Логирование
# Диспатч через with_first_found (без when для выбора init)

# ---- Валидация ----

- name: Validate keymap configuration
  ansible.builtin.include_tasks: validate/main.yml
  tags: ['keymap']

# ---- Настройка keymap ----

- name: Configure console keymap ({{ ansible_facts['service_mgr'] }})
  ansible.builtin.include_tasks: "{{ item }}"
  with_first_found:
    - files:
        - "init/{{ ansible_facts['service_mgr'] }}.yml"
      skip: true
  tags: ['keymap']

- name: Warn about unsupported init system for keymap
  ansible.builtin.debug:
    msg: >-
      WARNING: Console keymap skipped — init system
      '{{ ansible_facts['service_mgr'] }}' not supported.
      Supported: {{ _keymap_supported_inits | join(', ') }}.
  when: ansible_facts['service_mgr'] not in _keymap_supported_inits
  tags: ['keymap']

# ---- Проверка ----

- name: Verify console keymap
  ansible.builtin.include_tasks: "{{ item }}"
  with_first_found:
    - files:
        - "verify/{{ ansible_facts['service_mgr'] }}.yml"
      skip: true
  tags: ['keymap']

# ---- Логирование ----

- name: "Report: Console keymap"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_keymap_phases"
    _rpt_phase: "Console keymap"
    _rpt_status: "{{ 'done' if ansible_facts['service_mgr'] in _keymap_supported_inits else 'skip' }}"
    _rpt_detail: "{{ keymap_console }} ({{ ansible_facts['service_mgr'] }})"
  tags: ['keymap', 'report']

- name: "keymap — Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_keymap_phases"
    _rpt_title: "keymap"
  tags: ['keymap', 'report']
```

**Step 3: Run lint**

```bash
task lint
```

Expected: no errors.

**Step 4: Run molecule converge to verify it still works**

```bash
task test-keymap
```

Expected: PASS — validate should succeed with default `keymap_console: "us"`.

**Step 5: Commit**

```bash
git add ansible/roles/keymap/tasks/validate/main.yml \
        ansible/roles/keymap/tasks/main.yml
git commit -m "feat(keymap): add validate phase"
```

---

### Task 3: Create handlers/main.yml + add notify to init tasks

**Files:**
- Create: `ansible/roles/keymap/handlers/main.yml`
- Modify: `ansible/roles/keymap/tasks/init/systemd.yml`
- Modify: `ansible/roles/keymap/tasks/init/openrc.yml`
- Modify: `ansible/roles/keymap/tasks/init/runit.yml`

**Step 1: Create handlers/main.yml**

```yaml
---
# === Console keymap handlers ===

- name: Apply console keymap (systemd)
  ansible.builtin.systemd:
    name: systemd-vconsole-setup.service
    state: restarted
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Apply console keymap (openrc/runit)
  ansible.builtin.command: "loadkeys {{ keymap_console }}"
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] in ['openrc', 'runit']
  failed_when: false
  changed_when: false
```

**Step 2: Add notify to tasks/init/systemd.yml**

Replace content of `ansible/roles/keymap/tasks/init/systemd.yml`:

```yaml
---
# === Console keymap: systemd ===
# /etc/vconsole.conf

- name: Set console keymap (systemd)
  ansible.builtin.template:
    src: vconsole.conf.j2
    dest: /etc/vconsole.conf
    owner: root
    group: root
    mode: '0644'
  notify: apply keymap
  tags: ['keymap']
```

**Step 3: Add notify to tasks/init/openrc.yml**

Replace content of `ansible/roles/keymap/tasks/init/openrc.yml`:

```yaml
---
# === Console keymap: OpenRC ===
# /etc/conf.d/keymaps (Gentoo, Alpine)

- name: Set console keymap (OpenRC)
  ansible.builtin.lineinfile:
    path: /etc/conf.d/keymaps
    regexp: '^#?\s*keymap='
    line: 'keymap="{{ keymap_console }}"'
    create: true
    owner: root
    group: root
    mode: '0644'
  notify: apply keymap
  tags: ['keymap']
```

**Step 4: Add notify to tasks/init/runit.yml**

Replace content of `ansible/roles/keymap/tasks/init/runit.yml`:

```yaml
---
# === Console keymap: runit ===
# /etc/rc.conf KEYMAP= (Void Linux)

- name: Set console keymap (runit)
  ansible.builtin.lineinfile:
    path: /etc/rc.conf
    regexp: '^#?\s*KEYMAP='
    line: "KEYMAP={{ keymap_console }}"
    create: true
    owner: root
    group: root
    mode: '0644'
  notify: apply keymap
  tags: ['keymap']
```

**Step 5: Run lint**

```bash
task lint
```

Expected: no errors.

**Step 6: Run molecule test**

```bash
task test-keymap
```

Expected: PASS — handler fires on first converge (changed), skips on second (idempotent).

**Step 7: Commit**

```bash
git add ansible/roles/keymap/handlers/main.yml \
        ansible/roles/keymap/tasks/init/systemd.yml \
        ansible/roles/keymap/tasks/init/openrc.yml \
        ansible/roles/keymap/tasks/init/runit.yml
git commit -m "feat(keymap): add handler for immediate keymap apply after change"
```

---

### Task 4: Add verify/openrc.yml and verify/runit.yml

**Files:**
- Create: `ansible/roles/keymap/tasks/verify/openrc.yml`
- Create: `ansible/roles/keymap/tasks/verify/runit.yml`

**Step 1: Create tasks/verify/openrc.yml**

```yaml
---
# Проверка keymap (openrc — /etc/conf.d/keymaps)

- name: Verify console keymap (openrc)
  ansible.builtin.command: "grep -i 'keymap=\"{{ keymap_console }}\"' /etc/conf.d/keymaps"
  register: _keymap_check_openrc
  changed_when: false
  failed_when: _keymap_check_openrc.rc != 0
  tags: ['keymap']
```

**Step 2: Create tasks/verify/runit.yml**

```yaml
---
# Проверка keymap (runit — /etc/rc.conf)

- name: Verify console keymap (runit)
  ansible.builtin.command: "grep -i 'KEYMAP={{ keymap_console }}' /etc/rc.conf"
  register: _keymap_check_runit
  changed_when: false
  failed_when: _keymap_check_runit.rc != 0
  tags: ['keymap']
```

**Step 3: Run lint**

```bash
task lint
```

Expected: no errors.

**Step 4: Commit**

```bash
git add ansible/roles/keymap/tasks/verify/openrc.yml \
        ansible/roles/keymap/tasks/verify/runit.yml
git commit -m "feat(keymap): add verify tasks for openrc and runit"
```

---

### Task 5: Fix systemd verify — точный regex по "VC Keymap:" строке

**Files:**
- Modify: `ansible/roles/keymap/tasks/verify/systemd.yml`

**Problem:** Текущий assert `"keymap_console in _keymap_check.stdout"` — substring match по всему stdout. Для раскладки `us` это может совпасть с `X11 Layout: us` или другими полями. Нужен match именно строки `VC Keymap:`.

**Step 1: Replace tasks/verify/systemd.yml**

```yaml
---
# Проверка keymap (systemd — localectl доступен)

- name: Verify console keymap (systemd)
  ansible.builtin.command: localectl status
  register: _keymap_check
  changed_when: false
  tags: ['keymap']

- name: Assert keymap is set (systemd)
  ansible.builtin.assert:
    that:
      - "_keymap_check.stdout | regex_search('VC Keymap:\\s+' + keymap_console + '(\\s|$)')"
    fail_msg: >-
      Keymap '{{ keymap_console }}' not found as VC Keymap in localectl status.
      Output: {{ _keymap_check.stdout }}
    quiet: true
  when: _keymap_check is defined
  tags: ['keymap']
```

**Step 2: Run molecule test**

```bash
task test-keymap
```

Expected: PASS — regex должен найти `VC Keymap: us` в выводе localectl.

**Step 3: Commit**

```bash
git add ansible/roles/keymap/tasks/verify/systemd.yml
git commit -m "fix(keymap): use precise regex for VC Keymap field in systemd verify"
```

---

### Task 6: Fix molecule converge — убрать Arch-ограничение

**Files:**
- Modify: `ansible/roles/keymap/molecule/default/converge.yml`

**Problem:** Текущий `converge.yml` содержит `pre_tasks` с `assert os_family == Archlinux`. Это делает тест непригодным для Debian/Ubuntu/EL, которые задекларированы в `meta/main.yml`.

**Step 1: Replace converge.yml**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  roles:
    - role: keymap
      vars:
        keymap_console: "us"
```

**Step 2: Run molecule test**

```bash
task test-keymap
```

Expected: PASS.

**Step 3: Commit**

```bash
git add ansible/roles/keymap/molecule/default/converge.yml
git commit -m "test(keymap): remove Arch-only restriction from molecule converge"
```

---

### Task 7: Final lint + full test run

**Step 1: Run ansible-lint**

```bash
task lint
```

Expected: 0 errors, 0 warnings on keymap role.

**Step 2: Run keymap molecule test**

```bash
task test-keymap
```

Expected: syntax → converge → verify — все PASS.

**Step 3: Verify idempotency manually**

```bash
# В директории ansible/roles/keymap:
molecule converge && molecule converge
```

Expected: второй `converge` показывает `changed=0` для keymap tasks.

---

## Summary

| Task | Files | Type |
|------|-------|------|
| 1 | `defaults/main.yml` | chore |
| 2 | `tasks/validate/main.yml`, `tasks/main.yml` | feat |
| 3 | `handlers/main.yml`, `init/*.yml` ×3 | feat |
| 4 | `verify/openrc.yml`, `verify/runit.yml` | feat |
| 5 | `verify/systemd.yml` | fix |
| 6 | `molecule/default/converge.yml` | test |

После выполнения роль соответствует всем 8 бизнес-критериям из design doc.
