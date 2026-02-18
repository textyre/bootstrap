# locale role improvement — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the `locale` Ansible role to align with project patterns (keymap/timezone), remove Alpine/musl support, add input validation with soft-fail, fix the Void handler ordering bug, and improve Molecule test coverage.

**Architecture:** validate → generate → verify → configure order; soft-fail via `set_fact` flags rather than `assert`; `with_first_found + skip` for distro dispatch; four report phases feeding the common reporter.

**Tech Stack:** Ansible 2.15+, community.general.locale_gen, Molecule (ansible verifier), common role reporter.

**Design doc:** `docs/plans/2026-02-18-locale-role-improvement-design.md`

**Role path:** `ansible/roles/locale/`

---

### Task 1: Delete Alpine / musl files

**Files:**
- Delete: `ansible/roles/locale/tasks/generate/alpine.yml`
- Delete: `ansible/roles/locale/tasks/configure/musl.yml`
- Delete: `ansible/roles/locale/tasks/verify/musl.yml`
- Delete: `ansible/roles/locale/templates/locale-alpine.sh.j2`

**Step 1: Remove the four files**

```bash
rm ansible/roles/locale/tasks/generate/alpine.yml
rm ansible/roles/locale/tasks/configure/musl.yml
rm ansible/roles/locale/tasks/verify/musl.yml
rm ansible/roles/locale/templates/locale-alpine.sh.j2
```

**Step 2: Verify they are gone**

```bash
find ansible/roles/locale -name "*.yml" -o -name "*.j2" | sort
```

Expected: no alpine.yml, no musl.yml, no locale-alpine.sh.j2 in output.

**Step 3: Commit**

```bash
git add -A ansible/roles/locale/tasks/generate/alpine.yml \
           ansible/roles/locale/tasks/configure/musl.yml \
           ansible/roles/locale/tasks/verify/musl.yml \
           ansible/roles/locale/templates/locale-alpine.sh.j2
git commit -m "chore(locale): remove Alpine/musl support"
```

---

### Task 2: Create `vars/main.yml` with supported OS list

**Files:**
- Create: `ansible/roles/locale/vars/main.yml`

**Step 1: Create the file**

```yaml
# ansible/roles/locale/vars/main.yml
---
# Supported os_family values for locale generation
# Used in main.yml for with_first_found dispatch and unsupported-OS warning
_locale_supported_os_families:
  - archlinux
  - debian
  - redhat
  - void
```

**Step 2: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/vars/main.yml'))" && echo OK
```

Expected: `OK`

**Step 3: Commit**

```bash
git add ansible/roles/locale/vars/main.yml
git commit -m "feat(locale): add vars/main.yml with supported OS families list"
```

---

### Task 3: Create `tasks/validate/main.yml`

**Files:**
- Create: `ansible/roles/locale/tasks/validate/main.yml`

**Step 1: Create the directory and file**

```bash
mkdir -p ansible/roles/locale/tasks/validate
```

```yaml
# ansible/roles/locale/tasks/validate/main.yml
---
# === Валидация входных переменных ===
# Только проверка Ansible-переменных (без SSH, без системных вызовов).
# При любой ошибке: выставляет _locale_skip=true + _locale_skip_reason,
# НЕ падает — оборачивающий блок в main.yml проверяет _locale_skip.

- name: Check locale_list is not empty
  ansible.builtin.set_fact:
    _locale_skip: true
    _locale_skip_reason: "locale_list is empty"
  when: locale_list | length == 0
  tags: ['locale']

- name: Check locale_default is in locale_list
  ansible.builtin.set_fact:
    _locale_skip: true
    _locale_skip_reason: >-
      locale_default '{{ locale_default }}' not in
      locale_list {{ locale_list }}
  when:
    - not (_locale_skip | default(false))
    - locale_default not in locale_list
  tags: ['locale']

- name: Check LC_* override values are in locale_list
  ansible.builtin.set_fact:
    _locale_skip: true
    _locale_skip_reason: >-
      {{ item.key }}={{ item.value }} not in locale_list {{ locale_list }}
  loop: "{{ locale_lc_overrides | dict2items }}"
  when:
    - not (_locale_skip | default(false))
    - item.value not in locale_list
  tags: ['locale']

- name: Warn if locale config is invalid
  ansible.builtin.debug:
    msg: "WARNING: locale role skipped — {{ _locale_skip_reason }}"
  when: _locale_skip | default(false)
  tags: ['locale']
```

**Step 2: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/tasks/validate/main.yml'))" && echo OK
```

Expected: `OK`

**Step 3: Commit**

```bash
git add ansible/roles/locale/tasks/validate/main.yml
git commit -m "feat(locale): add validate/main.yml with soft-fail variable checks"
```

---

### Task 4: Fix Void handler ordering bug in `generate/void.yml`

**Files:**
- Modify: `ansible/roles/locale/tasks/generate/void.yml`

**Context:** The handler `Reconfigure glibc-locales (Void)` fires at end-of-play by default.
But `verify/glibc.yml` runs during the play. Without `flush_handlers`, verify sees stale
`locale -a` output (before `xbps-reconfigure` has run).

**Step 1: View current file**

```bash
cat ansible/roles/locale/tasks/generate/void.yml
```

**Step 2: Append flush_handlers task**

Add at the end of `ansible/roles/locale/tasks/generate/void.yml`:

```yaml
- name: Flush handlers (ensure xbps-reconfigure runs before verify)
  ansible.builtin.meta: flush_handlers
  tags: ['locale']
```

Full file after edit:

```yaml
---
# Генерация локалей (Void Linux)
# /etc/default/libc-locales + xbps-reconfigure

- name: Enable locales in libc-locales
  ansible.builtin.lineinfile:
    path: /etc/default/libc-locales
    regexp: '^#?\s*{{ item }}'
    line: "{{ item }} UTF-8"
    state: present
  loop: "{{ locale_list }}"
  notify: Reconfigure glibc-locales (Void)
  tags: ['locale']

- name: Flush handlers (ensure xbps-reconfigure runs before verify)
  ansible.builtin.meta: flush_handlers
  tags: ['locale']
```

**Step 3: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/tasks/generate/void.yml'))" && echo OK
```

Expected: `OK`

**Step 4: Commit**

```bash
git add ansible/roles/locale/tasks/generate/void.yml
git commit -m "fix(locale): flush handlers in void.yml before verify runs"
```

---

### Task 5: Replace `assert` in `verify/glibc.yml` with soft-fail

**Files:**
- Modify: `ansible/roles/locale/tasks/verify/glibc.yml`

**Context:** The current `assert` task crashes the play if a locale is missing. New behavior:
accumulate results into `_locale_verify_ok` (bool) and `_locale_verify_missing` (list), then
emit a debug warning. The caller (main.yml) reads `_locale_verify_ok` to decide whether to
run configure and what status to report.

**Step 1: Replace the file content**

```yaml
# ansible/roles/locale/tasks/verify/glibc.yml
---
# Проверка локалей (glibc)
# Soft-fail: выставляет _locale_verify_ok (bool) и _locale_verify_missing (list).
# НЕ крашит плей — main.yml читает _locale_verify_ok для репорта и configure.

- name: Get available locales
  ansible.builtin.command: locale -a
  register: _locale_check
  changed_when: false
  tags: ['locale']

- name: Check each requested locale is available
  ansible.builtin.set_fact:
    _locale_verify_ok: "{{ (_locale_verify_ok | default(true)) and (_locale_normalized in _available_list) }}"
    _locale_verify_missing: >-
      {{ (_locale_verify_missing | default([])) +
         ([] if _locale_normalized in _available_list else [item]) }}
  vars:
    _locale_normalized: "{{ item | lower | regex_replace('[\\-\\.]', '') }}"
    _available_list: "{{ _locale_check.stdout_lines | map('lower') | map('regex_replace', '[\\-\\.]', '') | list }}"
  loop: "{{ locale_list }}"
  tags: ['locale']

- name: Warn on missing locales
  ansible.builtin.debug:
    msg: >-
      WARNING: locale verify failed —
      missing: {{ _locale_verify_missing | join(', ') }}
  when: not (_locale_verify_ok | default(true))
  tags: ['locale']
```

**Step 2: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/tasks/verify/glibc.yml'))" && echo OK
```

Expected: `OK`

**Step 3: Commit**

```bash
git add ansible/roles/locale/tasks/verify/glibc.yml
git commit -m "fix(locale): replace assert with soft-fail in verify/glibc.yml"
```

---

### Task 6: Refactor `tasks/main.yml`

**Files:**
- Modify: `ansible/roles/locale/tasks/main.yml`

**Context:** New order: validate → generate → verify → configure. Generate uses
`with_first_found + skip: true` (like keymap role). Steps 2–4 are wrapped in a block
guarded by `when: not (_locale_skip | default(false))`. Four report phases replace the
single current phase.

**Step 1: Replace the file with the new content**

```yaml
# ansible/roles/locale/tasks/main.yml
---
# === Локализация ===
# validate → generate → verify → configure → report
# Soft-fail: ошибки конфига и генерации не крашат плей, но видны в репорте.

# ======================================================================
# ---- Валидация ----
# ======================================================================

- name: Validate locale configuration
  ansible.builtin.include_tasks: validate/main.yml
  tags: ['locale']

- name: "Report: Validate config"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_locale_phases"
    _rpt_phase: "Validate config"
    _rpt_status: "{{ 'fail' if (_locale_skip | default(false)) else 'done' }}"
    _rpt_detail: "{{ (_locale_skip_reason | default('')) | truncate(24, True) }}"
  tags: ['locale', 'report']

# ======================================================================
# ---- Generate / Verify / Configure (пропуск при невалидных переменных) ----
# ======================================================================

- name: Generate, verify and configure locale
  when: not (_locale_skip | default(false))
  block:

    # ---- Генерация локалей (дистро-специфик) ----

    - name: "Generate locales ({{ ansible_facts['os_family'] }})"
      ansible.builtin.include_tasks: "{{ item }}"
      with_first_found:
        - files:
            - "generate/{{ ansible_facts['os_family'] | lower }}.yml"
          skip: true
      tags: ['locale']

    - name: Warn about unsupported OS for locale generation
      ansible.builtin.debug:
        msg: >-
          WARNING: locale generation skipped —
          '{{ ansible_facts['os_family'] }}' not supported.
          Supported: {{ _locale_supported_os_families | join(', ') }}.
      when: ansible_facts['os_family'] | lower not in _locale_supported_os_families
      tags: ['locale']

    - name: "Report: Generate locales"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_locale_phases"
        _rpt_phase: "Generate locales"
        _rpt_status: "{{ 'skip' if ansible_facts['os_family'] | lower not in _locale_supported_os_families else 'done' }}"
        _rpt_detail: "{{ locale_list | join(', ') | truncate(24, True) }}"
      tags: ['locale', 'report']

    # ---- Проверка (до configure, чтобы не писать сломанный locale.conf) ----

    - name: Verify locale generation
      ansible.builtin.include_tasks: verify/glibc.yml
      tags: ['locale']

    - name: "Report: Verify locales"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_locale_phases"
        _rpt_phase: "Verify locales"
        _rpt_status: "{{ 'fail' if not (_locale_verify_ok | default(true)) else 'done' }}"
        _rpt_detail: >-
          {{
            (locale_list | length | string) + ' locales OK'
            if (_locale_verify_ok | default(true))
            else (_locale_verify_missing | default([]) | join(', ') | truncate(24, True))
          }}
      tags: ['locale', 'report']

    # ---- Настройка системной локали (только если verify прошёл) ----

    - name: Configure system locale
      ansible.builtin.include_tasks: configure/glibc.yml
      when: _locale_verify_ok | default(true)
      tags: ['locale']

    - name: "Report: Configure locale.conf"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_locale_phases"
        _rpt_phase: "Configure locale.conf"
        _rpt_status: "{{ 'skip' if not (_locale_verify_ok | default(true)) else 'done' }}"
        _rpt_detail: "{{ locale_default if (_locale_verify_ok | default(true)) else '' }}"
      tags: ['locale', 'report']

# ======================================================================
# ---- Итоговый отчёт ----
# ======================================================================

- name: "locale — Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_locale_phases"
    _rpt_title: "locale"
  tags: ['locale', 'report']
```

**Step 2: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/tasks/main.yml'))" && echo OK
```

Expected: `OK`

**Step 3: Run ansible-lint**

```bash
cd ansible && ansible-lint roles/locale/tasks/main.yml
```

Expected: no errors (warnings about `include_tasks` inside block are acceptable if present).

**Step 4: Commit**

```bash
git add ansible/roles/locale/tasks/main.yml
git commit -m "feat(locale): refactor main.yml — new order, with_first_found, soft-fail, 4 report phases"
```

---

### Task 7: Update `meta/main.yml` — remove Alpine

**Files:**
- Modify: `ansible/roles/locale/meta/main.yml`

**Step 1: View current file**

```bash
cat ansible/roles/locale/meta/main.yml
```

**Step 2: Remove Alpine entry from `platforms` list**

Remove this block from the `platforms` list:
```yaml
    - name: Alpine
      versions: [all]
```

Also update `description` to remove Alpine mention if present.

Final `platforms` list should be:
```yaml
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: EL
      versions: [all]
```

**Step 3: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/meta/main.yml'))" && echo OK
```

Expected: `OK`

**Step 4: Commit**

```bash
git add ansible/roles/locale/meta/main.yml
git commit -m "chore(locale): remove Alpine from meta platforms"
```

---

### Task 8: Add idempotency to `molecule/default/molecule.yml`

**Files:**
- Modify: `ansible/roles/locale/molecule/default/molecule.yml`

**Step 1: View current test_sequence**

```bash
cat ansible/roles/locale/molecule/default/molecule.yml
```

Current:
```yaml
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Step 2: Add idempotency between converge and verify**

```yaml
scenario:
  test_sequence:
    - syntax
    - converge
    - idempotency
    - verify
```

**Step 3: Verify syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/molecule/default/molecule.yml'))" && echo OK
```

Expected: `OK`

**Step 4: Commit**

```bash
git add ansible/roles/locale/molecule/default/molecule.yml
git commit -m "test(locale): add idempotency to molecule test sequence"
```

---

### Task 9: Enhance `molecule/default/verify.yml` — smoke test + LC_* assertions

**Files:**
- Modify: `ansible/roles/locale/molecule/default/verify.yml`

**Context:** Add two new checks after the existing `locale.conf` content checks:
1. Run `locale` command and assert `LANG=` appears in its stdout
2. Assert each `LC_*` override appears in the `locale` command output

The `locale` command reads the active locale from the environment and shows all variables.
Running it with `environment: {LANG: ..., LC_TIME: ...}` simulates a login shell with
the configured locale active.

**Step 1: View current verify.yml**

```bash
cat ansible/roles/locale/molecule/default/verify.yml
```

**Step 2: Append the smoke test tasks after the existing assertions**

Add these tasks at the end of the `tasks:` list in verify.yml:

```yaml
    - name: Run locale command (smoke test)
      ansible.builtin.command: locale
      register: _verify_locale_cmd
      changed_when: false
      environment: >-
        {{
          {'LANG': _test_locale} |
          combine(_test_lc_overrides)
        }}

    - name: Assert LANG is active in locale output
      ansible.builtin.assert:
        that:
          - "'LANG=' ~ _test_locale in _verify_locale_cmd.stdout"
        fail_msg: >-
          LANG={{ _test_locale }} not found in 'locale' output:
          {{ _verify_locale_cmd.stdout }}

    - name: Assert LC_* overrides are active in locale output
      ansible.builtin.assert:
        that:
          - "item.key ~ '=' ~ item.value in _verify_locale_cmd.stdout"
        fail_msg: >-
          {{ item.key }}={{ item.value }} not found in 'locale' output:
          {{ _verify_locale_cmd.stdout }}
      loop: "{{ _test_lc_overrides | dict2items }}"
```

**Step 3: Verify the full file parses correctly**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/locale/molecule/default/verify.yml'))" && echo OK
```

Expected: `OK`

**Step 4: Commit**

```bash
git add ansible/roles/locale/molecule/default/verify.yml
git commit -m "test(locale): add smoke locale command and LC_* override assertions to molecule verify"
```

---

### Task 10: Run ansible-lint on the whole role

**Step 1: Lint the role**

```bash
cd ansible && ansible-lint roles/locale/
```

Expected: no errors. Warnings about `include_tasks` inside `block` or `with_first_found` are acceptable — they are intentional patterns used across this project.

**Step 2: If errors found — fix them, re-lint, commit**

```bash
git add ansible/roles/locale/
git commit -m "fix(locale): address ansible-lint findings"
```

---

### Task 11: Run molecule test on remote VM

> See `/ansible` skill for how to run molecule tests on the remote VM.

**Step 1: Run molecule test**

```bash
cd ansible/roles/locale && molecule test
```

Expected sequence:
```
--> Test matrix: syntax, converge, idempotency, verify
...
PLAY RECAP ... ok=N changed=0 unreachable=0 failed=0  (idempotency)
...
TASK [Assert LANG is active in locale output] ... ok
TASK [Assert LC_* overrides are active in locale output] ... ok
```

**Step 2: If idempotency fails (changed > 0)**

Identify which task produced `changed`. Common causes:
- `template` task not using `ansible_managed` guard (already present in locale.conf.j2)
- `community.general.locale_gen` reporting changed when locale already exists

Fix the task, re-run `molecule test`.

**Step 3: Final commit if any fixes made**

```bash
git add ansible/roles/locale/
git commit -m "fix(locale): idempotency fixes after molecule run"
```
