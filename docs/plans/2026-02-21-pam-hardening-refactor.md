# pam_hardening Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix bugs in the pam_hardening role and add proper PAM stack activation for Arch, Void, and Fedora platforms.

**Architecture:** Platform-split tasks — `faillock.yml` acts as dispatcher, each platform gets its own file: `faillock_debian.yml` (pam-auth-update), `faillock_redhat.yml` (authselect), `faillock_arch.yml` (lineinfile). faillock.conf template extended with missing security options.

**Tech Stack:** Ansible 2.15+, Molecule (Docker), ansible-lint. Tests run via `task test-pam-hardening` on remote VM. Lint via `task lint`.

**Design doc:** `docs/plans/2026-02-21-pam-hardening-refactor-design.md`

---

## Task 1: Fix handler — `changed_when: true` → `changed_when: false`

**Files:**
- Modify: `ansible/roles/pam_hardening/handlers/main.yml`

**Step 1: Edit the handler**

In `ansible/roles/pam_hardening/handlers/main.yml`, change:

```yaml
- name: Update PAM configuration
  ansible.builtin.command: pam-auth-update --enable faillock
  changed_when: true
  when: ansible_facts['os_family'] == 'Debian'
```

To:

```yaml
- name: Update PAM (Debian)
  ansible.builtin.command: pam-auth-update --package
  changed_when: false
  when: ansible_facts['os_family'] == 'Debian'
```

Two changes: `--enable faillock` → `--package`, `changed_when: true` → `changed_when: false`.
Rename from "Update PAM configuration" to "Update PAM (Debian)" — new platform handlers will follow same naming.

**Step 2: Run lint**

```bash
task lint
```

Expected: no errors from this file.

**Step 3: Commit**

```bash
git add ansible/roles/pam_hardening/handlers/main.yml
git commit -m "fix(pam_hardening): handler -- use --package flag, changed_when: false"
```

---

## Task 2: Extend `defaults/main.yml` with new variables

**Files:**
- Modify: `ansible/roles/pam_hardening/defaults/main.yml`

**Step 1: Add new variables**

Append to `ansible/roles/pam_hardening/defaults/main.yml`:

```yaml
# even_deny_root: root аккаунт тоже подпадает под блокировку
# Стандарт: dev-sec (5223★), Kicksecure (576★), vmware/photon (3166★)
pam_faillock_even_deny_root: true

# local_users_only: faillock применяется только к локальным пользователям
# Установить true при наличии LDAP/SSO, чтобы избежать ложных блокировок
pam_faillock_local_users_only: false

# nodelay: убрать задержку после неудачного входа (pam >= 1.5.1)
pam_faillock_nodelay: false

# x11_skip: не учитывать попытки входа из X11-сессий (screensaver)
# Важно при deny=3 и GUI (lightdm/xorg) — иначе screensaver заблокирует аккаунт
pam_faillock_x11_skip: false
```

**Step 2: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 3: Commit**

```bash
git add ansible/roles/pam_hardening/defaults/main.yml
git commit -m "feat(pam_hardening): add even_deny_root, local_users_only, nodelay, x11_skip defaults"
```

---

## Task 3: Extend `faillock.conf.j2` template

**Files:**
- Modify: `ansible/roles/pam_hardening/templates/faillock.conf.j2`

**Step 1: Edit template**

Replace full content of `ansible/roles/pam_hardening/templates/faillock.conf.j2`:

```jinja2
# {{ ansible_managed }}
# PAM faillock configuration — brute-force protection
dir = /run/faillock
deny = {{ pam_faillock_deny }}
fail_interval = {{ pam_faillock_fail_interval }}
unlock_time = {{ pam_faillock_unlock_time }}
root_unlock_time = {{ pam_faillock_root_unlock_time }}
{% if pam_faillock_even_deny_root %}
even_deny_root
{% endif %}
{% if pam_faillock_audit %}
audit
{% endif %}
{% if pam_faillock_silent %}
silent
{% endif %}
{% if pam_faillock_local_users_only %}
local_users_only
{% endif %}
{% if pam_faillock_nodelay %}
nodelay
{% endif %}
```

**Step 2: Update molecule verify to assert `even_deny_root` is present**

In `ansible/roles/pam_hardening/molecule/default/verify.yml`, add after the existing `Verify faillock unlock_time setting` task:

```yaml
    - name: Verify faillock even_deny_root setting
      ansible.builtin.assert:
        that:
          - "'even_deny_root' in (_verify_faillock_content.content | b64decode)"
        fail_msg: "faillock.conf does not contain even_deny_root"
```

**Step 3: Run molecule test (should pass — Debian container)**

```bash
task test-pam-hardening
```

Expected: PASS (even_deny_root now in template with default true).

**Step 4: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ansible/roles/pam_hardening/templates/faillock.conf.j2 \
        ansible/roles/pam_hardening/molecule/default/verify.yml
git commit -m "feat(pam_hardening): extend faillock.conf.j2 -- even_deny_root, local_users_only, nodelay"
```

---

## Task 4: Create `tasks/faillock_debian.yml` — split pam-auth-update profiles

**Files:**
- Create: `ansible/roles/pam_hardening/tasks/faillock_debian.yml`

Two profiles instead of one (dev-sec/canonical pattern). Separate files for correct Auth-Final hook positioning.

**Step 1: Create file**

Create `ansible/roles/pam_hardening/tasks/faillock_debian.yml`:

```yaml
---
# === PAM faillock — Debian/Ubuntu ===
# Управление через pam-auth-update (правильный флаг: --package, не --enable)
# Два отдельных профиля: patten dev-sec (5223★), canonical/core-base

- name: Deploy pam-auth-update faillock preauth profile (Debian)
  ansible.builtin.copy:
    dest: /usr/share/pam-configs/faillock
    content: |
      Name: Enforce failed login attempt counter (preauth)
      Default: yes
      Priority: 0
      Auth-Type: Primary
      Auth:
        requisite  pam_faillock.so preauth
      Account-Type: Primary
      Account:
        required   pam_faillock.so
    owner: root
    group: root
    mode: '0644'
  notify: Update PAM (Debian)
  tags: ['pam', 'security', 'faillock']

- name: Deploy pam-auth-update faillock authfail profile (Debian)
  ansible.builtin.copy:
    dest: /usr/share/pam-configs/faillock-authfail
    content: |
      Name: Enforce failed login attempt counter (authfail)
      Default: yes
      Priority: 0
      Auth-Type: Primary
      Auth-Final:
        authfail   pam_faillock.so authfail
    owner: root
    group: root
    mode: '0644'
  notify: Update PAM (Debian)
  tags: ['pam', 'security', 'faillock']
```

**Step 2: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 3: Commit**

```bash
git add ansible/roles/pam_hardening/tasks/faillock_debian.yml
git commit -m "feat(pam_hardening): faillock_debian.yml -- split pam-auth-update profiles"
```

---

## Task 5: Create `tasks/faillock_redhat.yml` — authselect (Fedora)

**Files:**
- Create: `ansible/roles/pam_hardening/tasks/faillock_redhat.yml`

**Step 1: Create file**

Create `ansible/roles/pam_hardening/tasks/faillock_redhat.yml`:

```yaml
---
# === PAM faillock — Red Hat family (Fedora) ===
# authselect управляет PAM симлинками — прямое редактирование /etc/pam.d/ перезапишется
# Правильный паттерн: authselect enable-feature with-faillock
# Источник: ansible/product-demos (280★), ansible-lockdown/RHEL9-STIG (30★)

- name: Enable faillock feature via authselect (RedHat)
  ansible.builtin.command: authselect enable-feature with-faillock
  register: _pam_authselect_result
  changed_when: >
    'already' not in (_pam_authselect_result.stdout | default(''))
  notify: Apply authselect (RedHat)
  tags: ['pam', 'security', 'faillock']
```

**Step 2: Add handler for RedHat**

In `ansible/roles/pam_hardening/handlers/main.yml`, append:

```yaml
- name: Apply authselect (RedHat)
  ansible.builtin.command: authselect apply-changes
  changed_when: false
  when: ansible_facts['os_family'] == 'RedHat'
```

**Step 3: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 4: Commit**

```bash
git add ansible/roles/pam_hardening/tasks/faillock_redhat.yml \
        ansible/roles/pam_hardening/handlers/main.yml
git commit -m "feat(pam_hardening): faillock_redhat.yml -- authselect enable-feature with-faillock"
```

---

## Task 6: Create `tasks/faillock_arch.yml` — lineinfile (Arch, Void)

**Files:**
- Create: `ansible/roles/pam_hardening/tasks/faillock_arch.yml`

На Arch/Void нет ни authselect, ни pam-auth-update. PAM стек управляется напрямую через `/etc/pam.d/system-auth`. Строки добавляются без inline-параметров — конфиг берётся из faillock.conf. Паттерн подтверждён дистрибутивными файлами ataraxialinux и getsolus (supergrep).

**Step 1: Create file**

Create `ansible/roles/pam_hardening/tasks/faillock_arch.yml`:

```yaml
---
# === PAM faillock — Arch Linux / Void Linux ===
# Нет pam-auth-update и authselect — прямое управление /etc/pam.d/system-auth
# Параметры не указываются inline — они читаются из /etc/security/faillock.conf
# Паттерн: ataraxialinux, getsolus/packages (подтверждено supergrep)

# preauth: вставить перед строкой pam_unix.so в секции auth
- name: Insert pam_faillock preauth into system-auth (Arch/Void)
  ansible.builtin.lineinfile:
    path: /etc/pam.d/system-auth
    line: 'auth       required                    pam_faillock.so      preauth'
    insertbefore: '^auth.*pam_unix\.so'
    state: present
  tags: ['pam', 'security', 'faillock']

# authfail: вставить после строки pam_unix.so в секции auth
- name: Insert pam_faillock authfail into system-auth (Arch/Void)
  ansible.builtin.lineinfile:
    path: /etc/pam.d/system-auth
    line: 'auth       required                    pam_faillock.so      authfail'
    insertafter: '^auth.*pam_unix\.so'
    state: present
  tags: ['pam', 'security', 'faillock']

# account: добавить в секцию account
- name: Insert pam_faillock account into system-auth (Arch/Void)
  ansible.builtin.lineinfile:
    path: /etc/pam.d/system-auth
    line: 'account    required                    pam_faillock.so'
    insertafter: '^account'
    state: present
  tags: ['pam', 'security', 'faillock']
```

**Step 2: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 3: Commit**

```bash
git add ansible/roles/pam_hardening/tasks/faillock_arch.yml
git commit -m "feat(pam_hardening): faillock_arch.yml -- lineinfile for Arch/Void"
```

---

## Task 7: Refactor `tasks/faillock.yml` — dispatcher

**Files:**
- Modify: `ansible/roles/pam_hardening/tasks/faillock.yml`

**Step 1: Rewrite faillock.yml**

Replace full content of `ansible/roles/pam_hardening/tasks/faillock.yml`:

```yaml
---
# === PAM faillock — диспетчер ===
# 1. Записать faillock.conf (универсально, все платформы)
# 2. Активировать faillock в PAM стеке (зависит от платформы)

- name: Configure pam_faillock defaults
  ansible.builtin.template:
    src: faillock.conf.j2
    dest: /etc/security/faillock.conf
    owner: root
    group: root
    mode: '0644'
  tags: ['pam', 'security', 'faillock']

# Debian / Ubuntu — pam-auth-update
- name: Configure PAM stack (Debian)
  ansible.builtin.include_tasks: faillock_debian.yml
  when: ansible_facts['os_family'] == 'Debian'
  tags: ['pam', 'security', 'faillock']

# Fedora — authselect
- name: Configure PAM stack (RedHat/Fedora)
  ansible.builtin.include_tasks: faillock_redhat.yml
  when: ansible_facts['os_family'] == 'RedHat'
  tags: ['pam', 'security', 'faillock']

# Arch Linux / Void Linux — прямой lineinfile
- name: Configure PAM stack (Arch/Void)
  ansible.builtin.include_tasks: faillock_arch.yml
  when: ansible_facts['os_family'] in ['Archlinux', 'Void']
  tags: ['pam', 'security', 'faillock']
```

**Step 2: Run molecule test**

```bash
task test-pam-hardening
```

Expected: PASS (Debian container — faillock_debian.yml вызывается).

**Step 3: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 4: Commit**

```bash
git add ansible/roles/pam_hardening/tasks/faillock.yml
git commit -m "refactor(pam_hardening): faillock.yml -- platform dispatcher, include_tasks per OS"
```

---

## Task 8: Update `meta/main.yml` — убрать EL, добавить Fedora и Void

**Files:**
- Modify: `ansible/roles/pam_hardening/meta/main.yml`

**Step 1: Edit meta**

Replace content of `ansible/roles/pam_hardening/meta/main.yml`:

```yaml
---
galaxy_info:
  role_name: pam_hardening
  author: textyre
  description: PAM security hardening — faillock brute-force protection
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: Fedora
      versions: [all]
  galaxy_tags: [security, pam, hardening, faillock]
dependencies: []
```

Note: Void Linux не является официальной Galaxy platform, поэтому не добавляется в список, но поддерживается через `os_family == 'Void'`.

**Step 2: Commit**

```bash
git add ansible/roles/pam_hardening/meta/main.yml
git commit -m "chore(pam_hardening): meta -- remove EL, add Fedora; update description"
```

---

## Task 9: Update `molecule/default/verify.yml` — расширить проверки

**Files:**
- Modify: `ansible/roles/pam_hardening/molecule/default/verify.yml`

**Step 1: Add verify for pam-auth-update profiles and PAM stack**

Replace content of `ansible/roles/pam_hardening/molecule/default/verify.yml`:

```yaml
---
# Molecule verify playbook for pam_hardening role

- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  tasks:
    - name: Check faillock.conf exists
      ansible.builtin.stat:
        path: /etc/security/faillock.conf
      register: _verify_faillock_conf
      failed_when: not _verify_faillock_conf.stat.exists

    - name: Slurp faillock.conf
      ansible.builtin.slurp:
        src: /etc/security/faillock.conf
      register: _verify_faillock_content

    - name: Verify faillock deny setting
      ansible.builtin.assert:
        that:
          - "'deny =' in (_verify_faillock_content.content | b64decode)"
        fail_msg: "faillock.conf does not contain deny setting"

    - name: Verify faillock unlock_time setting
      ansible.builtin.assert:
        that:
          - "'unlock_time =' in (_verify_faillock_content.content | b64decode)"
        fail_msg: "faillock.conf does not contain unlock_time setting"

    - name: Verify faillock even_deny_root setting
      ansible.builtin.assert:
        that:
          - "'even_deny_root' in (_verify_faillock_content.content | b64decode)"
        fail_msg: "faillock.conf does not contain even_deny_root (root would be exempt from lockout)"

    # Debian-specific: pam-auth-update profiles должны существовать
    - name: Check pam-auth-update faillock profile exists (Debian)
      ansible.builtin.stat:
        path: /usr/share/pam-configs/faillock
      register: _verify_pam_profile
      failed_when: not _verify_pam_profile.stat.exists
      when: ansible_facts['os_family'] == 'Debian'

    - name: Check pam-auth-update faillock-authfail profile exists (Debian)
      ansible.builtin.stat:
        path: /usr/share/pam-configs/faillock-authfail
      register: _verify_pam_authfail_profile
      failed_when: not _verify_pam_authfail_profile.stat.exists
      when: ansible_facts['os_family'] == 'Debian'

    - name: Show test results
      ansible.builtin.debug:
        msg:
          - "All pam_hardening checks passed!"
          - "faillock.conf: exists and configured with even_deny_root"
          - "PAM profiles: deployed correctly for {{ ansible_facts['os_family'] }}"
```

**Step 2: Run molecule test**

```bash
task test-pam-hardening
```

Expected: PASS (все новые assert'ы проходят).

**Step 3: Run lint**

```bash
task lint
```

Expected: PASS.

**Step 4: Commit**

```bash
git add ansible/roles/pam_hardening/molecule/default/verify.yml
git commit -m "test(pam_hardening): molecule verify -- even_deny_root, split pam profiles"
```

---

## Task 10: Update README.md — добавить pam_hardening в таблицу ролей

**Files:**
- Modify: `README.md`

**Step 1: Add pam_hardening to roles table**

In `README.md`, в таблице ролей добавить строку после `package_manager` (до `vm`):

```markdown
| 5.5 | `pam_hardening` | PAM faillock — защита от brute-force (Arch, Ubuntu, Fedora) |
```

Точное место: после строки с `package_manager`, перед `vm`.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add pam_hardening to roles table in README"
```

---

## Task 11: Final — полный прогон проверок

**Step 1: Syntax check**

```bash
task check
```

Expected: PASS — no syntax errors.

**Step 2: Lint**

```bash
task lint
```

Expected: PASS — no ansible-lint violations.

**Step 3: Molecule test**

```bash
task test-pam-hardening
```

Expected: PASS — все задачи идемпотентны, все verify assert'ы проходят.

**Step 4: Idempotency check**

Убедиться что повторный прогон converge не сообщает changed (кроме handler). Если molecule настроен на idempotency check — он сделает это автоматически.

---

## Итог

После выполнения всех задач:

| Было | Стало |
|------|-------|
| `changed_when: true` в handler | `changed_when: false` |
| `--enable faillock` | `--package` |
| `even_deny_root` отсутствует | `even_deny_root` включён по умолчанию |
| EL задекларирован, не работает | EL убран, добавлен Fedora |
| Arch/Void: faillock.conf пишется, но PAM стек не изменён | `lineinfile` активирует faillock в `/etc/pam.d/system-auth` |
| Один pam-auth-update профиль | Два профиля (faillock + faillock-authfail) |
| Нет `local_users_only`, `nodelay`, `x11_skip` | Переменные с документированными дефолтами |

**Следующий шаг (вне scope):** роль `pwquality_hardening` — password complexity policy.
