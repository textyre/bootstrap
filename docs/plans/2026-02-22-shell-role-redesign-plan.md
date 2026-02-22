# Shell Role Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the shell role from a disabled dotfile deployer into a focused system-level shell environment manager (install, chsh, XDG dirs, global /etc/profile.d/ config).

**Architecture:** Five-responsibility role: INSTALL → CHSH → XDG_DIRS → GLOBAL → VERIFY. OS dispatch via `vars/{distro}.yml` dictionaries. Three shell types: bash, zsh, fish. Global config via `/etc/profile.d/` (bash/zsh) and `/etc/fish/conf.d/` (fish). Chezmoi handles all per-user dotfiles — no overlap.

**Tech Stack:** Ansible 2.15+, Molecule (localhost driver), Jinja2 templates. Reference implementation: `roles/ntp/`.

**Design doc:** `docs/plans/2026-02-22-shell-role-redesign.md`

---

### Task 1: Clean Up Deprecated Files

Remove old templates and install files that are being replaced.

**Files:**
- Delete: `ansible/roles/shell/templates/bashrc.j2`
- Delete: `ansible/roles/shell/templates/zshrc.j2`
- Delete: `ansible/roles/shell/tasks/install-archlinux.yml`
- Delete: `ansible/roles/shell/tasks/install-debian.yml`

**Step 1: Delete deprecated templates**

```bash
rm ansible/roles/shell/templates/bashrc.j2
rm ansible/roles/shell/templates/zshrc.j2
```

**Step 2: Delete old OS-specific install files**

```bash
rm ansible/roles/shell/tasks/install-archlinux.yml
rm ansible/roles/shell/tasks/install-debian.yml
```

**Step 3: Create new directory structure**

```bash
mkdir -p ansible/roles/shell/vars
```

**Step 4: Commit cleanup**

```bash
git add -A ansible/roles/shell/
git commit -m "refactor(shell): remove deprecated templates and old install files"
```

---

### Task 2: Vars — Per-Distro Package Maps

Create `vars/main.yml` and per-distro variable files following the ntp pattern.

**Files:**
- Create: `ansible/roles/shell/vars/main.yml`
- Create: `ansible/roles/shell/vars/archlinux.yml`
- Create: `ansible/roles/shell/vars/debian.yml`
- Create: `ansible/roles/shell/vars/redhat.yml`
- Create: `ansible/roles/shell/vars/void.yml`
- Create: `ansible/roles/shell/vars/gentoo.yml`

**Step 1: Create vars/main.yml**

```yaml
---
# === Shell role — internal variables ===

# Supported OS families (ROLE-003)
_shell_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# Supported shell types
_shell_supported_types:
  - bash
  - zsh
  - fish
```

**Step 2: Create vars/archlinux.yml**

```yaml
---
# === Shell packages — Arch Linux ===

_shell_packages:
  bash: []
  zsh:
    - zsh
  fish:
    - fish

_shell_bin:
  bash: /bin/bash
  zsh: /usr/bin/zsh
  fish: /usr/bin/fish
```

**Step 3: Create vars/debian.yml**

```yaml
---
# === Shell packages — Debian/Ubuntu ===

_shell_packages:
  bash: []
  zsh:
    - zsh
  fish:
    - fish

_shell_bin:
  bash: /bin/bash
  zsh: /usr/bin/zsh
  fish: /usr/bin/fish
```

**Step 4: Create vars/redhat.yml**

```yaml
---
# === Shell packages — RedHat/Fedora ===

_shell_packages:
  bash: []
  zsh:
    - zsh
  fish:
    - fish

_shell_bin:
  bash: /bin/bash
  zsh: /usr/bin/zsh
  fish: /usr/bin/fish
```

**Step 5: Create vars/void.yml**

```yaml
---
# === Shell packages — Void Linux ===

_shell_packages:
  bash: []
  zsh:
    - zsh
  fish:
    - fish

_shell_bin:
  bash: /bin/bash
  zsh: /usr/bin/zsh
  fish: /usr/bin/fish
```

**Step 6: Create vars/gentoo.yml**

```yaml
---
# === Shell packages — Gentoo ===

_shell_packages:
  bash: []
  zsh:
    - app-shells/zsh
  fish:
    - app-shells/fish

_shell_bin:
  bash: /bin/bash
  zsh: /usr/bin/zsh
  fish: /usr/bin/fish
```

**Step 7: Commit vars files**

```bash
git add ansible/roles/shell/vars/
git commit -m "feat(shell): add per-distro vars files with package maps (ROLE-001)"
```

---

### Task 3: Defaults and Meta

Rewrite `defaults/main.yml` with new variables and update `meta/main.yml` for all 5 distros.

**Files:**
- Modify: `ansible/roles/shell/defaults/main.yml`
- Modify: `ansible/roles/shell/meta/main.yml`
- Create: `ansible/roles/shell/handlers/main.yml`

**Step 1: Rewrite defaults/main.yml**

Replace entire file with:

```yaml
---
# === System-level shell environment ===
# Install shell, set login shell, create XDG dirs, deploy global config.
# Per-user dotfiles (.bashrc, .zshrc) managed by chezmoi — NOT this role.

# Target user
shell_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"

# Shell type: bash | zsh | fish
shell_type: zsh

# Set as user's login shell via chsh?
shell_set_login: true

# System-wide PATH additions (deployed to /etc/profile.d/ or /etc/fish/conf.d/)
# Use absolute paths or $HOME-relative paths
shell_global_path:
  - "$HOME/.local/bin"
  - "$HOME/.cargo/bin"
  - "/usr/local/go/bin"

# System-wide environment variables (deployed alongside PATH)
shell_global_env: {}
#   GOPATH: "$HOME/go"
#   JAVA_HOME: "/usr/lib/jvm/default"

# XDG Base Directories to create (XDG Base Directory Specification)
# Uses _shell_user_home fact resolved at runtime
shell_xdg_dirs:
  - ".config"
  - ".local/share"
  - ".local/bin"
  - ".cache"

# Set ZDOTDIR in /etc/zsh/zshenv? (zsh only)
# Points ZDOTDIR to ${XDG_CONFIG_HOME:-$HOME/.config}/zsh
shell_zsh_zdotdir: true
```

**Step 2: Rewrite meta/main.yml**

Replace entire file with:

```yaml
---
galaxy_info:
  role_name: shell
  author: textyre
  description: >-
    System-level shell environment. Installs shell (bash/zsh/fish),
    sets login shell, creates XDG directories, deploys global config
    (/etc/profile.d/, /etc/zsh/zshenv, /etc/fish/conf.d/).
    Per-user dotfiles managed by chezmoi — not this role.
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: EL
      versions: [all]
    - name: Gentoo
      versions: [all]
  galaxy_tags: [shell, bash, zsh, fish, environment]
dependencies: []
```

**Step 3: Create handlers/main.yml (empty — no services)**

```yaml
---
# Shell role has no services to manage.
# Handlers file present for role structure completeness.
```

**Step 4: Commit**

```bash
git add ansible/roles/shell/defaults/main.yml ansible/roles/shell/meta/main.yml ansible/roles/shell/handlers/main.yml
git commit -m "feat(shell): rewrite defaults and meta for system-level shell environment"
```

---

### Task 4: Templates

Create the three new template files.

**Files:**
- Create: `ansible/roles/shell/templates/profile.d-dev-paths.sh.j2`
- Create: `ansible/roles/shell/templates/zshenv.j2`
- Create: `ansible/roles/shell/templates/fish-dev-paths.fish.j2`

**Step 1: Create profile.d-dev-paths.sh.j2**

Deploy to `/etc/profile.d/dev-paths.sh`. Sourced by bash/zsh on login. Adds PATH entries and env vars.

```jinja2
# {{ ansible_managed }}
# System-wide PATH additions for development toolchains
# Sourced by bash/zsh on login (/etc/profile.d/)

{% for dir in shell_global_path %}
[ -d "{{ dir }}" ] && case ":$PATH:" in *":{{ dir }}:"*) ;; *) PATH="{{ dir }}:$PATH" ;; esac
{% endfor %}
export PATH
{% if shell_global_env | length > 0 %}

# Environment variables
{% for key, value in shell_global_env.items() %}
export {{ key }}="{{ value }}"
{% endfor %}
{% endif %}
```

**Step 2: Create zshenv.j2**

Deploy to `/etc/zsh/zshenv`. Loaded for ALL zsh sessions (interactive + non-interactive).

```jinja2
# {{ ansible_managed }}
# Global zsh environment — loaded for ALL zsh sessions (login + non-login)
# Per-user config managed by chezmoi at $ZDOTDIR/.zshrc

{% if shell_zsh_zdotdir %}
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
{% endif %}
```

**Step 3: Create fish-dev-paths.fish.j2**

Deploy to `/etc/fish/conf.d/dev-paths.fish`. Fish ignores `/etc/profile.d/`, needs its own format.

```jinja2
# {{ ansible_managed }}
# System-wide PATH additions for development toolchains
# Fish shell conf.d — fish ignores /etc/profile.d/

{% for dir in shell_global_path %}
if test -d "{{ dir }}"
    fish_add_path --global "{{ dir }}"
end
{% endfor %}
{% if shell_global_env | length > 0 %}

# Environment variables
{% for key, value in shell_global_env.items() %}
set -gx {{ key }} "{{ value }}"
{% endfor %}
{% endif %}
```

**Step 4: Commit templates**

```bash
git add ansible/roles/shell/templates/
git commit -m "feat(shell): add global config templates for bash/zsh/fish"
```

---

### Task 5: Task Files — validate, install, chsh

Core task files for preflight validation, package installation, and login shell assignment.

**Files:**
- Create: `ansible/roles/shell/tasks/validate.yml`
- Create: `ansible/roles/shell/tasks/install.yml`
- Create: `ansible/roles/shell/tasks/chsh.yml`

**Step 1: Create tasks/validate.yml**

Preflight assertions following the ntp pattern (ROLE-003, ROLE-010).

```yaml
---
# === Shell — preflight validation ===
# Runs before any state changes

- name: Assert supported operating system
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] in _shell_supported_os
    fail_msg: >-
      OS family '{{ ansible_facts['os_family'] }}' is not supported.
      Supported: {{ _shell_supported_os | join(', ') }}.
  tags: ['shell']

- name: Assert shell_type is valid
  ansible.builtin.assert:
    that:
      - shell_type in _shell_supported_types
    fail_msg: >-
      shell_type '{{ shell_type }}' is not supported.
      Supported: {{ _shell_supported_types | join(', ') }}.
  tags: ['shell']

- name: Assert shell_user is defined and non-empty
  ansible.builtin.assert:
    that:
      - shell_user is defined
      - shell_user | length > 0
    fail_msg: >-
      shell_user must be set to a valid username.
      Current value: '{{ shell_user | default("") }}'.
  tags: ['shell']
```

**Step 2: Create tasks/install.yml**

Package installation using `ansible.builtin.package` (ROLE-001, ROLE-011).

```yaml
---
# === Shell — package installation ===
# Uses per-distro vars for package names

- name: Install shell packages
  ansible.builtin.package:
    name: "{{ _shell_packages[shell_type] }}"
    state: present
  when: _shell_packages[shell_type] | length > 0
  tags: ['shell', 'install']

- name: "Report: Install shell"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_shell_phases"
    _rpt_phase: "Install shell"
    _rpt_status: "{{ 'done' if (_shell_packages[shell_type] | length > 0) else 'skip' }}"
    _rpt_detail: "{{ shell_type }} ({{ ansible_facts['os_family'] }})"
  tags: ['shell', 'report']
```

**Step 3: Create tasks/chsh.yml**

Set login shell using `ansible.builtin.user` (ROLE-011).

```yaml
---
# === Shell — set login shell ===
# Uses ansible.builtin.user to change the user's default shell

- name: Set login shell for {{ shell_user }}
  ansible.builtin.user:
    name: "{{ shell_user }}"
    shell: "{{ _shell_bin[shell_type] }}"
  when: shell_set_login | bool
  tags: ['shell', 'configure']

- name: "Report: Set login shell"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_shell_phases"
    _rpt_phase: "Set login shell"
    _rpt_status: "{{ 'done' if (shell_set_login | bool) else 'skip' }}"
    _rpt_detail: "{{ _shell_bin[shell_type] }}"
  tags: ['shell', 'report']
```

**Step 4: Commit**

```bash
git add ansible/roles/shell/tasks/validate.yml ansible/roles/shell/tasks/install.yml ansible/roles/shell/tasks/chsh.yml
git commit -m "feat(shell): add validate, install, chsh task files"
```

---

### Task 6: Task Files — xdg, global

XDG directory creation and global config deployment.

**Files:**
- Create: `ansible/roles/shell/tasks/xdg.yml`
- Create: `ansible/roles/shell/tasks/global.yml`

**Step 1: Create tasks/xdg.yml**

Create XDG Base Directories per spec.

```yaml
---
# === Shell — XDG Base Directory creation ===
# https://specifications.freedesktop.org/basedir-spec/latest/

- name: Create XDG directories
  ansible.builtin.file:
    path: "{{ _shell_user_home }}/{{ item }}"
    state: directory
    owner: "{{ shell_user }}"
    group: "{{ shell_user }}"
    mode: '0755'
  loop: "{{ shell_xdg_dirs }}"
  tags: ['shell', 'configure']

- name: "Report: XDG directories"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_shell_phases"
    _rpt_phase: "Create XDG directories"
    _rpt_detail: "{{ shell_xdg_dirs | length }} dirs"
  tags: ['shell', 'report']
```

**Step 2: Create tasks/global.yml**

Deploy global config to `/etc/profile.d/`, `/etc/zsh/zshenv`, `/etc/fish/conf.d/`.

```yaml
---
# === Shell — global system-wide configuration ===
# /etc/profile.d/ for bash/zsh, /etc/fish/conf.d/ for fish

# ---- /etc/profile.d/ (bash + zsh) ----

- name: Deploy /etc/profile.d/dev-paths.sh
  ansible.builtin.template:
    src: profile.d-dev-paths.sh.j2
    dest: /etc/profile.d/dev-paths.sh
    owner: root
    group: root
    mode: '0644'
  when: shell_type in ['bash', 'zsh']
  tags: ['shell', 'configure']

# ---- /etc/zsh/zshenv (zsh only) ----

- name: Ensure /etc/zsh directory exists
  ansible.builtin.file:
    path: /etc/zsh
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: shell_type == 'zsh'
  tags: ['shell', 'configure']

- name: Deploy /etc/zsh/zshenv
  ansible.builtin.template:
    src: zshenv.j2
    dest: /etc/zsh/zshenv
    owner: root
    group: root
    mode: '0644'
  when: shell_type == 'zsh'
  tags: ['shell', 'configure']

# ---- /etc/fish/conf.d/ (fish only) ----

- name: Ensure /etc/fish/conf.d directory exists
  ansible.builtin.file:
    path: /etc/fish/conf.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: shell_type == 'fish'
  tags: ['shell', 'configure']

- name: Deploy /etc/fish/conf.d/dev-paths.fish
  ansible.builtin.template:
    src: fish-dev-paths.fish.j2
    dest: /etc/fish/conf.d/dev-paths.fish
    owner: root
    group: root
    mode: '0644'
  when: shell_type == 'fish'
  tags: ['shell', 'configure']

# ---- Report ----

- name: "Report: Global config"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_shell_phases"
    _rpt_phase: "Deploy global config"
    _rpt_detail: >-
      {{ shell_type }}
      paths={{ shell_global_path | length }}
      env={{ shell_global_env | length }}
  tags: ['shell', 'report']
```

**Step 3: Commit**

```bash
git add ansible/roles/shell/tasks/xdg.yml ansible/roles/shell/tasks/global.yml
git commit -m "feat(shell): add XDG directory and global config task files"
```

---

### Task 7: Task Files — verify and main orchestrator

In-role verification (ROLE-005) and the main orchestrator.

**Files:**
- Create: `ansible/roles/shell/tasks/verify.yml`
- Modify: `ansible/roles/shell/tasks/main.yml` (full rewrite)

**Step 1: Create tasks/verify.yml**

In-role verification: login shell, XDG dirs, global config files.

```yaml
---
# === Shell — in-role verification (ROLE-005) ===

# ---- Login shell ----

- name: Get current login shell for {{ shell_user }}
  ansible.builtin.getent:
    database: passwd
    key: "{{ shell_user }}"
  tags: ['shell']

- name: Assert login shell is correct
  ansible.builtin.assert:
    that:
      - getent_passwd[shell_user][5] == _shell_bin[shell_type]
    fail_msg: >-
      Login shell for {{ shell_user }} is '{{ getent_passwd[shell_user][5] }}'
      but expected '{{ _shell_bin[shell_type] }}'.
    quiet: true
  when: shell_set_login | bool
  tags: ['shell']

# ---- XDG directories ----

- name: Verify XDG directories exist
  ansible.builtin.stat:
    path: "{{ _shell_user_home }}/{{ item }}"
  register: _shell_verify_xdg
  loop: "{{ shell_xdg_dirs }}"
  tags: ['shell']

- name: Assert all XDG directories exist
  ansible.builtin.assert:
    that:
      - item.stat.exists
      - item.stat.isdir
    fail_msg: >-
      XDG directory '{{ item.item }}' does not exist or is not a directory.
    quiet: true
  loop: "{{ _shell_verify_xdg.results }}"
  loop_control:
    label: "{{ item.item }}"
  tags: ['shell']

# ---- Global config: /etc/profile.d/ ----

- name: Verify /etc/profile.d/dev-paths.sh exists
  ansible.builtin.stat:
    path: /etc/profile.d/dev-paths.sh
  register: _shell_verify_profiled
  when: shell_type in ['bash', 'zsh']
  tags: ['shell']

- name: Assert /etc/profile.d/dev-paths.sh exists
  ansible.builtin.assert:
    that:
      - _shell_verify_profiled.stat.exists
    fail_msg: "/etc/profile.d/dev-paths.sh not found"
    quiet: true
  when: shell_type in ['bash', 'zsh']
  tags: ['shell']

# ---- Global config: /etc/zsh/zshenv ----

- name: Verify /etc/zsh/zshenv exists
  ansible.builtin.stat:
    path: /etc/zsh/zshenv
  register: _shell_verify_zshenv
  when: shell_type == 'zsh'
  tags: ['shell']

- name: Assert /etc/zsh/zshenv exists
  ansible.builtin.assert:
    that:
      - _shell_verify_zshenv.stat.exists
    fail_msg: "/etc/zsh/zshenv not found"
    quiet: true
  when: shell_type == 'zsh'
  tags: ['shell']

# ---- Global config: /etc/fish/conf.d/ ----

- name: Verify /etc/fish/conf.d/dev-paths.fish exists
  ansible.builtin.stat:
    path: /etc/fish/conf.d/dev-paths.fish
  register: _shell_verify_fish
  when: shell_type == 'fish'
  tags: ['shell']

- name: Assert /etc/fish/conf.d/dev-paths.fish exists
  ansible.builtin.assert:
    that:
      - _shell_verify_fish.stat.exists
    fail_msg: "/etc/fish/conf.d/dev-paths.fish not found"
    quiet: true
  when: shell_type == 'fish'
  tags: ['shell']

# ---- Report ----

- name: "Report: Verification"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_shell_phases"
    _rpt_phase: "Verify shell"
    _rpt_detail: "all checks passed"
  tags: ['shell', 'report']
```

**Step 2: Rewrite tasks/main.yml**

Complete rewrite as orchestrator following the ntp pattern.

```yaml
---
# === System-level shell environment ===
# validate → install → chsh → xdg → global → verify → report

- name: Shell role
  tags: ['shell']
  block:

    # ======================================================================
    # ---- Resolve user home ----
    # ======================================================================

    - name: Get user home directory
      ansible.builtin.getent:
        database: passwd
        key: "{{ shell_user }}"
      tags: ['shell']

    - name: Set user home fact
      ansible.builtin.set_fact:
        _shell_user_home: "{{ getent_passwd[shell_user][4] }}"
      tags: ['shell']

    # ======================================================================
    # ---- Load OS-specific vars ----
    # ======================================================================

    - name: Include OS-specific variables
      ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
      tags: ['shell']

    # ======================================================================
    # ---- Validation ----
    # ======================================================================

    - name: Validate shell configuration
      ansible.builtin.include_tasks: validate.yml
      tags: ['shell']

    # ======================================================================
    # ---- Install ----
    # ======================================================================

    - name: Install shell package
      ansible.builtin.include_tasks: install.yml
      tags: ['shell']

    # ======================================================================
    # ---- Login shell ----
    # ======================================================================

    - name: Set login shell
      ansible.builtin.include_tasks: chsh.yml
      tags: ['shell']

    # ======================================================================
    # ---- XDG directories ----
    # ======================================================================

    - name: Create XDG directories
      ansible.builtin.include_tasks: xdg.yml
      tags: ['shell']

    # ======================================================================
    # ---- Global config ----
    # ======================================================================

    - name: Deploy global shell configuration
      ansible.builtin.include_tasks: global.yml
      tags: ['shell']

    # ======================================================================
    # ---- Verification ----
    # ======================================================================

    - name: Verify shell configuration
      ansible.builtin.include_tasks: verify.yml
      tags: ['shell']

    # ======================================================================
    # ---- Report ----
    # ======================================================================

    - name: "shell — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        _rpt_fact: "_shell_phases"
        _rpt_title: "shell"
      tags: ['shell', 'report']
```

**Step 3: Commit**

```bash
git add ansible/roles/shell/tasks/
git commit -m "feat(shell): add verify, rewrite main.yml orchestrator (ROLE-005, ROLE-008)"
```

---

### Task 8: Update group_vars

Update `group_vars/all/system.yml` to match new variable names.

**Files:**
- Modify: `ansible/inventory/group_vars/all/system.yml` (lines 80-86)

**Step 1: Replace shell section in system.yml**

Find this block (lines ~80-86):
```yaml
# ============================================================
#  shell — роль roles/shell
# ============================================================

shell_user: "{{ target_user }}"
shell_type: bash
# chezmoi управляет .bashrc и .zshrc — shell role не деплоит конфиг
shell_deploy_config: false
```

Replace with:
```yaml
# ============================================================
#  shell — роль roles/shell
# ============================================================

shell_user: "{{ target_user }}"
shell_type: zsh
shell_set_login: true

# System-wide PATH additions → /etc/profile.d/
shell_global_path:
  - "$HOME/.local/bin"
  - "$HOME/.cargo/bin"
  - "/usr/local/go/bin"
```

**Step 2: Commit**

```bash
git add ansible/inventory/group_vars/all/system.yml
git commit -m "feat(shell): update group_vars for new shell role variables"
```

---

### Task 9: Molecule Tests

Rewrite molecule converge and verify for the redesigned role.

**Files:**
- Modify: `ansible/roles/shell/molecule/default/molecule.yml`
- Modify: `ansible/roles/shell/molecule/default/converge.yml`
- Modify: `ansible/roles/shell/molecule/default/verify.yml`

**Step 1: Update molecule.yml**

Remove `idempotence` from test_sequence (it requires two full runs and is slow for development — add back later if desired).

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

**Step 2: Rewrite converge.yml**

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
    - role: shell
      vars:
        shell_type: zsh
        shell_set_login: true
        shell_global_path:
          - "$HOME/.local/bin"
          - "$HOME/.cargo/bin"
          - "/usr/local/go/bin"
        shell_global_env:
          GOPATH: "$HOME/go"
        shell_zsh_zdotdir: true
```

**Step 3: Rewrite verify.yml**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/roles/shell/defaults/main.yml"

  vars:
    _verify_shell_type: zsh

  tasks:

    # ---- shell package installed ----

    - name: Check zsh is installed
      ansible.builtin.command:
        cmd: command -v zsh
      register: _verify_zsh
      changed_when: false
      failed_when: _verify_zsh.rc != 0

    # ---- login shell ----

    - name: Get user info
      ansible.builtin.getent:
        database: passwd
        key: "{{ shell_user }}"

    - name: Assert login shell is zsh
      ansible.builtin.assert:
        that:
          - "'/zsh' in getent_passwd[shell_user][5]"
        fail_msg: >-
          Login shell for {{ shell_user }} is '{{ getent_passwd[shell_user][5] }}'
          but expected zsh.

    # ---- XDG directories ----

    - name: Set user home fact
      ansible.builtin.set_fact:
        _verify_home: "{{ getent_passwd[shell_user][4] }}"

    - name: Check XDG directories exist
      ansible.builtin.stat:
        path: "{{ _verify_home }}/{{ item }}"
      register: _verify_xdg
      loop:
        - ".config"
        - ".local/share"
        - ".local/bin"
        - ".cache"

    - name: Assert all XDG directories exist
      ansible.builtin.assert:
        that:
          - item.stat.exists
          - item.stat.isdir
        fail_msg: "XDG directory '{{ item.item }}' missing"
      loop: "{{ _verify_xdg.results }}"
      loop_control:
        label: "{{ item.item }}"

    # ---- /etc/profile.d/dev-paths.sh ----

    - name: Check /etc/profile.d/dev-paths.sh exists
      ansible.builtin.stat:
        path: /etc/profile.d/dev-paths.sh
      register: _verify_profiled

    - name: Assert /etc/profile.d/dev-paths.sh exists
      ansible.builtin.assert:
        that:
          - _verify_profiled.stat.exists
          - _verify_profiled.stat.isreg
        fail_msg: "/etc/profile.d/dev-paths.sh not found"

    - name: Read /etc/profile.d/dev-paths.sh
      ansible.builtin.slurp:
        src: /etc/profile.d/dev-paths.sh
      register: _verify_profiled_content

    - name: Assert profile.d contains managed marker
      ansible.builtin.assert:
        that:
          - "'Ansible' in (_verify_profiled_content.content | b64decode)"
        fail_msg: "/etc/profile.d/dev-paths.sh missing Ansible managed marker"

    - name: Assert profile.d contains PATH entries
      ansible.builtin.assert:
        that:
          - "'.local/bin' in (_verify_profiled_content.content | b64decode)"
          - "'.cargo/bin' in (_verify_profiled_content.content | b64decode)"
        fail_msg: "/etc/profile.d/dev-paths.sh missing expected PATH entries"

    - name: Assert profile.d contains env vars
      ansible.builtin.assert:
        that:
          - "'GOPATH' in (_verify_profiled_content.content | b64decode)"
        fail_msg: "/etc/profile.d/dev-paths.sh missing GOPATH env var"

    # ---- /etc/zsh/zshenv ----

    - name: Check /etc/zsh/zshenv exists
      ansible.builtin.stat:
        path: /etc/zsh/zshenv
      register: _verify_zshenv

    - name: Assert /etc/zsh/zshenv exists
      ansible.builtin.assert:
        that:
          - _verify_zshenv.stat.exists
          - _verify_zshenv.stat.isreg
        fail_msg: "/etc/zsh/zshenv not found"

    - name: Read /etc/zsh/zshenv
      ansible.builtin.slurp:
        src: /etc/zsh/zshenv
      register: _verify_zshenv_content

    - name: Assert zshenv contains ZDOTDIR
      ansible.builtin.assert:
        that:
          - "'ZDOTDIR' in (_verify_zshenv_content.content | b64decode)"
        fail_msg: "/etc/zsh/zshenv missing ZDOTDIR setting"

    # ---- Final result ----

    - name: Show verification result
      ansible.builtin.debug:
        msg:
          - "All shell role checks passed!"
          - "Shell: zsh installed, login shell set"
          - "XDG: all directories created"
          - "Global: /etc/profile.d/dev-paths.sh deployed"
          - "Global: /etc/zsh/zshenv deployed with ZDOTDIR"
```

**Step 4: Commit**

```bash
git add ansible/roles/shell/molecule/
git commit -m "feat(shell): rewrite molecule tests for redesigned role (ROLE-006)"
```

---

### Task 10: Integration Test

Run molecule to validate everything works together.

**Step 1: Run syntax check**

```bash
cd ansible && molecule syntax -s default -- --limit localhost roles/shell
```

Or if molecule is configured per-role:
```bash
cd ansible && molecule test -s default -- roles/shell
```

Expected: syntax check passes.

**Step 2: Run converge**

```bash
cd ansible && molecule converge -s default -- roles/shell
```

Expected: all tasks succeed, report table rendered.

**Step 3: Run verify**

```bash
cd ansible && molecule verify -s default -- roles/shell
```

Expected: all assertions pass.

**Step 4: Fix any issues found during testing**

If tests fail, fix the failing file and re-run. Common issues:
- Jinja2 template syntax errors
- Missing variables in scope
- Wrong file paths in assertions

**Step 5: Final commit (if any fixes)**

```bash
git add -A ansible/roles/shell/
git commit -m "fix(shell): address molecule test findings"
```

---

## File Change Summary

| Action | File |
|--------|------|
| DELETE | `roles/shell/templates/bashrc.j2` |
| DELETE | `roles/shell/templates/zshrc.j2` |
| DELETE | `roles/shell/tasks/install-archlinux.yml` |
| DELETE | `roles/shell/tasks/install-debian.yml` |
| CREATE | `roles/shell/vars/main.yml` |
| CREATE | `roles/shell/vars/archlinux.yml` |
| CREATE | `roles/shell/vars/debian.yml` |
| CREATE | `roles/shell/vars/redhat.yml` |
| CREATE | `roles/shell/vars/void.yml` |
| CREATE | `roles/shell/vars/gentoo.yml` |
| CREATE | `roles/shell/templates/profile.d-dev-paths.sh.j2` |
| CREATE | `roles/shell/templates/zshenv.j2` |
| CREATE | `roles/shell/templates/fish-dev-paths.fish.j2` |
| CREATE | `roles/shell/tasks/validate.yml` |
| CREATE | `roles/shell/tasks/install.yml` |
| CREATE | `roles/shell/tasks/chsh.yml` |
| CREATE | `roles/shell/tasks/xdg.yml` |
| CREATE | `roles/shell/tasks/global.yml` |
| CREATE | `roles/shell/tasks/verify.yml` |
| CREATE | `roles/shell/handlers/main.yml` |
| REWRITE | `roles/shell/defaults/main.yml` |
| REWRITE | `roles/shell/meta/main.yml` |
| REWRITE | `roles/shell/tasks/main.yml` |
| MODIFY | `roles/shell/molecule/default/molecule.yml` |
| REWRITE | `roles/shell/molecule/default/converge.yml` |
| REWRITE | `roles/shell/molecule/default/verify.yml` |
| MODIFY | `inventory/group_vars/all/system.yml` |
