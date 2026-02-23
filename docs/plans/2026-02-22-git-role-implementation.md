# Git Role Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the git Ansible role from a minimal 7-setting config into a full developer toolchain with two-level architecture, multi-user support, commit signing, aliases, LFS, credential helper, and full role-requirements.md compliance.

**Architecture:** Two-level design — system layer (root, runs once: install packages, create directories) and per-user layer (become_user, loops over owner + additional users: git config, signing, aliases, credential, LFS init). All features gated by per-subsystem boolean toggles following ROLE-010 pattern.

**Tech Stack:** Ansible 2.15+, `community.general.git_config` module, `ansible.builtin.package` for installation, molecule for testing.

**Design doc:** `docs/plans/2026-02-22-git-role-redesign.md`

**Reference implementations:** `ansible/roles/ntp/` (full compliance example), `ansible/roles/user/` (per-user loop pattern, profile-aware defaults)

---

## Task 1: defaults/main.yml — Complete data model

**Files:**
- Modify: `ansible/roles/git/defaults/main.yml` (replace entirely)

**Step 1: Write defaults/main.yml**

Replace the existing file with the complete data model from the design doc:

```yaml
---
# === git role — defaults ===

# --- ROLE-003: Supported operating systems ---
_git_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# --- Primary owner ---
git_owner:
  name: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
  user_name: ""
  user_email: ""
  signing_method: none
  signing_key: ""
  credential_helper: ""

# --- Additional users ---
git_additional_users: []
# - name: alice
#   user_name: "Alice"
#   user_email: "alice@example.com"
#   signing_method: none
#   signing_key: ""
#   credential_helper: ""

# --- Shared defaults (applied to all users) ---
git_default_branch: main
git_editor: vim
git_pull_rebase: true
git_push_autosetup_remote: true
git_core_autocrlf: input
git_commit_sign: >-
  {{ true if 'security' in (workstation_profiles | default([]))
     else false }}

# --- Per-subsystem toggles (ROLE-010) ---
git_manage_signing: >-
  {{ true if 'developer' in (workstation_profiles | default([]))
     or 'security' in (workstation_profiles | default([]))
     else false }}
git_manage_aliases: true
git_manage_credential: true
git_manage_hooks: false
git_lfs_enabled: true

# --- Aliases ---
git_aliases_preset:
  st: status
  co: checkout
  br: branch
  ci: commit
  lg: "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
  unstage: "reset HEAD --"
  last: "log -1 HEAD"
  amend: "commit --amend --no-edit"
git_aliases_extra: {}
git_aliases_overwrite: {}

# --- Credential helper ---
git_credential_helper: "cache --timeout=3600"

# --- Global hooks ---
git_hooks_path: "~/.config/git/hooks"

# --- Extra git config (ROLE-010 dict pattern) ---
git_config_extra: {}
git_config_overwrite: {}

# --- Safe directory (CVE-2022-24765) ---
git_safe_directories: []
```

**Step 2: Verify syntax**

Run: `ansible-playbook --syntax-check` (via remote executor on VM)

Expected: No errors — file is valid YAML.

**Step 3: Commit**

```bash
git add ansible/roles/git/defaults/main.yml
git commit -m "feat(git): rewrite defaults/main.yml with complete data model (ROLE-003, ROLE-009, ROLE-010)"
```

---

## Task 2: vars/ per-distro files

**Files:**
- Create: `ansible/roles/git/vars/archlinux.yml`
- Create: `ansible/roles/git/vars/debian.yml`
- Create: `ansible/roles/git/vars/redhat.yml`
- Create: `ansible/roles/git/vars/void.yml`
- Create: `ansible/roles/git/vars/gentoo.yml`

**Step 1: Write all five vars files**

Each file defines `_git_packages` (list) and `_git_lfs_package` (string):

```yaml
# vars/archlinux.yml
---
_git_packages:
  - git
_git_lfs_package: git-lfs
```

```yaml
# vars/debian.yml
---
_git_packages:
  - git
_git_lfs_package: git-lfs
```

```yaml
# vars/redhat.yml
---
_git_packages:
  - git
_git_lfs_package: git-lfs
```

```yaml
# vars/void.yml
---
_git_packages:
  - git
_git_lfs_package: git-lfs
```

```yaml
# vars/gentoo.yml
---
_git_packages:
  - dev-vcs/git
_git_lfs_package: dev-vcs/git-lfs
```

**Note:** Gentoo uses category/package naming (`dev-vcs/git`). All others use `git` / `git-lfs`.

**Step 2: Commit**

```bash
git add ansible/roles/git/vars/
git commit -m "feat(git): add per-distro vars/ files (ROLE-001)"
```

---

## Task 3: tasks/install.yml — System layer package installation

**Files:**
- Create: `ansible/roles/git/tasks/install.yml`

**Step 1: Write install.yml**

```yaml
---
# === git — package installation (system layer) ===

- name: Install git
  ansible.builtin.package:
    name: "{{ _git_packages }}"
    state: present
  tags: [git, install]

- name: Install git-lfs
  ansible.builtin.package:
    name: "{{ _git_lfs_package }}"
    state: present
  when: git_lfs_enabled | bool
  tags: [git, install, lfs]
```

**Step 2: Commit**

```bash
git add ansible/roles/git/tasks/install.yml
git commit -m "feat(git): add install.yml — git + git-lfs packages (ROLE-001, ROLE-011)"
```

---

## Task 4: tasks/hooks_global.yml — Global hooks directory

**Files:**
- Create: `ansible/roles/git/tasks/hooks_global.yml`

**Step 1: Write hooks_global.yml**

```yaml
---
# === git — global hooks directory (system layer) ===
# Creates the directory only. Hook scripts are deployed by dotfiles/chezmoi.

- name: Ensure global hooks directory exists
  ansible.builtin.file:
    path: "{{ git_hooks_path }}"
    state: directory
    owner: "{{ _git_current_user.name }}"
    mode: "0755"
  loop: "{{ [git_owner] + git_additional_users }}"
  loop_control:
    loop_var: _git_current_user
    label: "{{ _git_current_user.name }}"
  when: git_manage_hooks | bool
  tags: [git, hooks]
```

**Step 2: Commit**

```bash
git add ansible/roles/git/tasks/hooks_global.yml
git commit -m "feat(git): add hooks_global.yml — create global hooks directory"
```

---

## Task 5: Per-user task files — config_base.yml, config_extra.yml

**Files:**
- Create: `ansible/roles/git/tasks/config_base.yml`
- Create: `ansible/roles/git/tasks/config_extra.yml`

**Step 1: Write config_base.yml**

```yaml
---
# === git — base configuration (per-user layer) ===
# Sets core git settings: user.name, user.email, init.defaultBranch, core.editor,
# pull.rebase, push.autoSetupRemote, core.autocrlf, safe.directory.
# Runs as become_user via _git_current_user from configure_user.yml loop.

- name: Set git user.name
  community.general.git_config:
    name: user.name
    value: "{{ _git_current_user.user_name }}"
    scope: global
  when: (_git_current_user.user_name | default('')) | length > 0
  tags: [git, configure]

- name: Set git user.email
  community.general.git_config:
    name: user.email
    value: "{{ _git_current_user.user_email }}"
    scope: global
  when: (_git_current_user.user_email | default('')) | length > 0
  tags: [git, configure]

- name: Set git init.defaultBranch
  community.general.git_config:
    name: init.defaultBranch
    value: "{{ git_default_branch }}"
    scope: global
  tags: [git, configure]

- name: Set git core.editor
  community.general.git_config:
    name: core.editor
    value: "{{ git_editor }}"
    scope: global
  tags: [git, configure]

- name: Set git pull.rebase
  community.general.git_config:
    name: pull.rebase
    value: "{{ git_pull_rebase | string | lower }}"
    scope: global
  tags: [git, configure]

- name: Set git push.autoSetupRemote
  community.general.git_config:
    name: push.autoSetupRemote
    value: "{{ git_push_autosetup_remote | string | lower }}"
    scope: global
  tags: [git, configure]

- name: Set git core.autocrlf
  community.general.git_config:
    name: core.autocrlf
    value: "{{ git_core_autocrlf }}"
    scope: global
  tags: [git, configure]

- name: Set git safe.directory
  community.general.git_config:
    name: safe.directory
    value: "{{ item }}"
    scope: global
  loop: "{{ git_safe_directories }}"
  when: git_safe_directories | length > 0
  tags: [git, configure, security]
```

**Step 2: Write config_extra.yml**

```yaml
---
# === git — extra configuration (per-user layer) ===
# Applies arbitrary git config from git_config_extra + git_config_overwrite dicts.
# Runs as become_user via _git_current_user from configure_user.yml loop.

- name: Set extra git config entries
  community.general.git_config:
    name: "{{ item.key }}"
    value: "{{ item.value | string }}"
    scope: global
  loop: "{{ git_config_extra | combine(git_config_overwrite) | dict2items }}"
  loop_control:
    label: "{{ item.key }}"
  when: (git_config_extra | combine(git_config_overwrite)) | length > 0
  tags: [git, configure]
```

**Step 3: Commit**

```bash
git add ansible/roles/git/tasks/config_base.yml ansible/roles/git/tasks/config_extra.yml
git commit -m "feat(git): add config_base.yml and config_extra.yml (per-user layer)"
```

---

## Task 6: Per-user task files — signing.yml, aliases.yml, credential.yml, lfs_user.yml

**Files:**
- Create: `ansible/roles/git/tasks/signing.yml`
- Create: `ansible/roles/git/tasks/aliases.yml`
- Create: `ansible/roles/git/tasks/credential.yml`
- Create: `ansible/roles/git/tasks/lfs_user.yml`

**Step 1: Write signing.yml**

```yaml
---
# === git — commit signing configuration (per-user layer) ===
# Supports SSH signing (git 2.34+) and GPG signing.
# Signing method is per-user via _git_current_user.signing_method.

- name: Configure SSH commit signing
  when: (_git_current_user.signing_method | default('none')) == 'ssh'
  tags: [git, signing]
  block:
    - name: Set gpg.format to ssh
      community.general.git_config:
        name: gpg.format
        value: ssh
        scope: global

    - name: Set user.signingKey (SSH)
      community.general.git_config:
        name: user.signingKey
        value: "{{ _git_current_user.signing_key }}"
        scope: global

    - name: Set commit.gpgSign
      community.general.git_config:
        name: commit.gpgSign
        value: "{{ git_commit_sign | string | lower }}"
        scope: global

- name: Configure GPG commit signing
  when: (_git_current_user.signing_method | default('none')) == 'gpg'
  tags: [git, signing]
  block:
    - name: Set user.signingKey (GPG)
      community.general.git_config:
        name: user.signingKey
        value: "{{ _git_current_user.signing_key }}"
        scope: global

    - name: Set commit.gpgSign
      community.general.git_config:
        name: commit.gpgSign
        value: "{{ git_commit_sign | string | lower }}"
        scope: global
```

**Step 2: Write aliases.yml**

```yaml
---
# === git — aliases (per-user layer) ===
# Three-layer merge: preset → extra → overwrite.

- name: Set git aliases
  community.general.git_config:
    name: "alias.{{ item.key }}"
    value: "{{ item.value }}"
    scope: global
  loop: "{{ git_aliases_preset | combine(git_aliases_extra) | combine(git_aliases_overwrite) | dict2items }}"
  loop_control:
    label: "{{ item.key }}"
  tags: [git, aliases]
```

**Step 3: Write credential.yml**

```yaml
---
# === git — credential helper (per-user layer) ===

- name: Set git credential.helper
  community.general.git_config:
    name: credential.helper
    value: "{{ _git_current_user.credential_helper | default(git_credential_helper, true) }}"
    scope: global
  tags: [git, credential]
```

**Step 4: Write lfs_user.yml**

```yaml
---
# === git — LFS per-user init (per-user layer) ===
# Runs `git lfs install --skip-repo` to set up LFS hooks in user's gitconfig.

- name: Initialize git-lfs for user
  ansible.builtin.command:
    cmd: git lfs install --skip-repo
  register: _git_lfs_init
  changed_when: "'Updated' in _git_lfs_init.stdout"
  tags: [git, lfs]
```

**Step 5: Commit**

```bash
git add ansible/roles/git/tasks/signing.yml ansible/roles/git/tasks/aliases.yml ansible/roles/git/tasks/credential.yml ansible/roles/git/tasks/lfs_user.yml
git commit -m "feat(git): add signing, aliases, credential, lfs_user task files (per-user layer)"
```

---

## Task 7: tasks/configure_user.yml — Per-user dispatcher

**Files:**
- Create: `ansible/roles/git/tasks/configure_user.yml`

**Step 1: Write configure_user.yml**

This file is called once per user from the main.yml loop. It dispatches to all per-user task files with appropriate guards.

```yaml
---
# === git — per-user configuration dispatcher ===
# Called from main.yml with _git_current_user set by loop_var.
# Each include_tasks runs as become_user: _git_current_user.name.

- name: "Configure git for {{ _git_current_user.name }}"
  become: true
  become_user: "{{ _git_current_user.name }}"
  tags: [git, configure]
  block:
    - name: Apply base git config
      ansible.builtin.include_tasks: config_base.yml

    - name: Apply extra git config
      ansible.builtin.include_tasks: config_extra.yml
      when: (git_config_extra | combine(git_config_overwrite)) | length > 0

    - name: Configure commit signing
      ansible.builtin.include_tasks: signing.yml
      when: git_manage_signing | bool

    - name: Configure git aliases
      ansible.builtin.include_tasks: aliases.yml
      when: git_manage_aliases | bool

    - name: Configure credential helper
      ansible.builtin.include_tasks: credential.yml
      when: git_manage_credential | bool

    - name: Initialize git-lfs
      ansible.builtin.include_tasks: lfs_user.yml
      when: git_lfs_enabled | bool

    - name: Set core.hooksPath
      community.general.git_config:
        name: core.hooksPath
        value: "{{ git_hooks_path }}"
        scope: global
      when: git_manage_hooks | bool
      tags: [git, hooks]
```

**Step 2: Commit**

```bash
git add ansible/roles/git/tasks/configure_user.yml
git commit -m "feat(git): add configure_user.yml — per-user dispatcher"
```

---

## Task 8: tasks/verify.yml — In-role verification (ROLE-005)

**Files:**
- Create: `ansible/roles/git/tasks/verify.yml`

**Step 1: Write verify.yml**

```yaml
---
# === git — in-role verification (ROLE-005) ===

- name: Verify git is installed
  ansible.builtin.command:
    cmd: git --version
  register: _git_verify_installed
  changed_when: false
  failed_when: _git_verify_installed.rc != 0
  tags: [git]

- name: Verify git config for owner  # noqa: command-instead-of-module
  become: true
  become_user: "{{ git_owner.name }}"
  ansible.builtin.command:
    cmd: git config --global --get user.name
  register: _git_verify_username
  changed_when: false
  failed_when: _git_verify_username.rc != 0
  when: (git_owner.user_name | default('')) | length > 0
  tags: [git]

- name: Assert owner user.name matches expected
  ansible.builtin.assert:
    that:
      - _git_verify_username.stdout == git_owner.user_name
    fail_msg: >-
      git user.name mismatch: expected '{{ git_owner.user_name }}',
      got '{{ _git_verify_username.stdout }}'
    quiet: true
  when:
    - (git_owner.user_name | default('')) | length > 0
    - _git_verify_username is not skipped
  tags: [git]

- name: Verify commit signing is configured  # noqa: command-instead-of-module
  become: true
  become_user: "{{ git_owner.name }}"
  ansible.builtin.command:
    cmd: git config --global --get commit.gpgSign
  register: _git_verify_signing
  changed_when: false
  failed_when: false
  when:
    - git_manage_signing | bool
    - (git_owner.signing_method | default('none')) != 'none'
  tags: [git]

- name: Assert commit signing is enabled
  ansible.builtin.assert:
    that:
      - _git_verify_signing.stdout == (git_commit_sign | string | lower)
    fail_msg: "commit.gpgSign expected '{{ git_commit_sign | string | lower }}', got '{{ _git_verify_signing.stdout }}'"
    quiet: true
  when:
    - git_manage_signing | bool
    - (git_owner.signing_method | default('none')) != 'none'
    - _git_verify_signing is not skipped
  tags: [git]

- name: Verify git-lfs is installed
  ansible.builtin.command:
    cmd: git lfs version
  register: _git_verify_lfs
  changed_when: false
  failed_when: _git_verify_lfs.rc != 0
  when: git_lfs_enabled | bool
  tags: [git, lfs]

- name: Verify hooks directory exists
  ansible.builtin.stat:
    path: "{{ git_hooks_path | replace('~', '/home/' ~ git_owner.name) }}"
  register: _git_verify_hooks_dir
  when: git_manage_hooks | bool
  tags: [git, hooks]

- name: Assert hooks directory exists
  ansible.builtin.assert:
    that:
      - _git_verify_hooks_dir.stat.exists
      - _git_verify_hooks_dir.stat.isdir
    fail_msg: "Global hooks directory {{ git_hooks_path }} does not exist"
    quiet: true
  when:
    - git_manage_hooks | bool
    - _git_verify_hooks_dir is not skipped
  tags: [git, hooks]
```

**Step 2: Commit**

```bash
git add ansible/roles/git/tasks/verify.yml
git commit -m "feat(git): add verify.yml — in-role verification (ROLE-005)"
```

---

## Task 9: tasks/main.yml — Orchestrator rewrite

**Files:**
- Modify: `ansible/roles/git/tasks/main.yml` (replace entirely)

**Step 1: Write main.yml**

Replace the entire file with the orchestrator:

```yaml
---
# === git role — main orchestration ===
# Two-level architecture:
#   System layer (root): preflight, install, hooks directory
#   Per-user layer (become_user): config, signing, aliases, credential, LFS

# ======================================================================
# ---- ROLE-003: Preflight ----
# ======================================================================

- name: Assert supported operating system
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] in _git_supported_os
    fail_msg: >-
      OS family '{{ ansible_facts['os_family'] }}' is not supported.
      Supported: {{ _git_supported_os | join(', ') }}
    success_msg: "OS family '{{ ansible_facts['os_family'] }}' is supported"
  tags: [git]

# ======================================================================
# ---- ROLE-001: Load OS-specific variables ----
# ======================================================================

- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [git]

# ROLE-008: Report preflight
- name: "Report: preflight"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_phase: "Preflight"
    _rpt_detail: "os={{ ansible_facts['os_family'] }}"
  tags: [git, report]

# ======================================================================
# ---- System layer: install packages ----
# ======================================================================

- name: Install git packages
  ansible.builtin.include_tasks: install.yml
  tags: [git, install]

# ROLE-008: Report install
- name: "Report: install"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_phase: "Install"
    _rpt_detail: >-
      packages={{ _git_packages | join(', ') }}
      lfs={{ git_lfs_enabled }}
  tags: [git, report]

# ======================================================================
# ---- System layer: global hooks directory ----
# ======================================================================

- name: Create global hooks directories
  ansible.builtin.include_tasks: hooks_global.yml
  when: git_manage_hooks | bool
  tags: [git, hooks]

# ======================================================================
# ---- Per-user layer: configure each user ----
# ======================================================================

- name: Configure git for each user
  ansible.builtin.include_tasks: configure_user.yml
  loop: "{{ [git_owner] + git_additional_users }}"
  loop_control:
    loop_var: _git_current_user
    label: "{{ _git_current_user.name }}"
  tags: [git, configure]

# ROLE-008: Report user configuration
- name: "Report: user configuration"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_phase: "Configure users"
    _rpt_detail: >-
      owner={{ git_owner.name }}
      additional={{ git_additional_users | length }}
  tags: [git, report]

# ======================================================================
# ---- ROLE-005: Verification ----
# ======================================================================

- name: Verify git configuration
  ansible.builtin.include_tasks: verify.yml
  tags: [git]

# ROLE-008: Report verification
- name: "Report: verification"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_phase: "Verify"
    _rpt_detail: "all checks passed"
  tags: [git, report]

# ======================================================================
# ---- ROLE-008: Final report ----
# ======================================================================

- name: "git -- Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_title: "git"
  tags: [git, report]
```

**Step 2: Run syntax check on VM**

Run (via remote executor):
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook ansible/playbooks/workstation.yml --syntax-check --tags git"
```

Expected: No syntax errors.

**Step 3: Commit**

```bash
git add ansible/roles/git/tasks/main.yml
git commit -m "feat(git): rewrite main.yml — two-level orchestrator (ROLE-003, ROLE-001, ROLE-005, ROLE-008)"
```

---

## Task 10: meta/main.yml — Update metadata

**Files:**
- Modify: `ansible/roles/git/meta/main.yml` (replace entirely)

**Step 1: Write meta/main.yml**

```yaml
---
galaxy_info:
  role_name: git
  author: textyre
  description: >-
    Git configuration and developer toolchain: install, global config,
    commit signing (SSH/GPG), aliases, credential helper, LFS, global hooks.
    Multi-user support with per-subsystem toggles. CIS-aligned safe.directory.
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: Fedora
      versions: [all]
    - name: Void Linux
      versions: [all]
    - name: Gentoo
      versions: [all]
  galaxy_tags: [git, configuration, signing, lfs, developer]
dependencies: []
```

**Step 2: Commit**

```bash
git add ansible/roles/git/meta/main.yml
git commit -m "feat(git): update meta/main.yml — all 5 platforms, expanded description"
```

---

## Task 11: Molecule tests — molecule.yml, converge.yml, verify.yml

**Files:**
- Modify: `ansible/roles/git/molecule/default/molecule.yml` (replace)
- Modify: `ansible/roles/git/molecule/default/converge.yml` (replace)
- Modify: `ansible/roles/git/molecule/default/verify.yml` (replace)

**Step 1: Write molecule.yml**

```yaml
---
driver:
  name: default
platforms:
  - name: instance
    managed: false
provisioner:
  name: ansible
  inventory:
    host_vars:
      instance:
        ansible_connection: local
        git_owner:
          name: "{{ lookup('env', 'USER') }}"
          user_name: "Test User"
          user_email: "test@example.com"
          signing_method: none
          signing_key: ""
          credential_helper: ""
        git_manage_hooks: true
        git_hooks_path: "/tmp/test-git-hooks"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
verifier:
  name: ansible
scenario:
  test_sequence:
    - syntax
    - converge
    - idempotence
    - verify
```

**Step 2: Write converge.yml**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  pre_tasks:
    - name: Assert test environment
      ansible.builtin.assert:
        that: ansible_facts['os_family'] == 'Archlinux'

  roles:
    - role: git
```

**Step 3: Write verify.yml**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  tasks:
    # ---- git installed ----

    - name: Verify git is installed
      ansible.builtin.command:
        cmd: git --version
      register: _git_verify_installed
      changed_when: false
      failed_when: _git_verify_installed.rc != 0

    # ---- base config ----

    - name: Check git user.name  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get user.name
      register: _git_verify_username
      changed_when: false
      failed_when: _git_verify_username.stdout != git_owner.user_name

    - name: Check git user.email  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get user.email
      register: _git_verify_email
      changed_when: false
      failed_when: _git_verify_email.stdout != git_owner.user_email

    - name: Check git init.defaultBranch  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get init.defaultBranch
      register: _git_verify_branch
      changed_when: false
      failed_when: _git_verify_branch.stdout != 'main'

    - name: Check git core.editor  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get core.editor
      register: _git_verify_editor
      changed_when: false
      failed_when: _git_verify_editor.stdout != 'vim'

    - name: Check git pull.rebase  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get pull.rebase
      register: _git_verify_rebase
      changed_when: false
      failed_when: _git_verify_rebase.stdout != 'true'

    - name: Check git push.autoSetupRemote  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get push.autoSetupRemote
      register: _git_verify_autosetup
      changed_when: false
      failed_when: _git_verify_autosetup.stdout != 'true'

    - name: Check git core.autocrlf  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get core.autocrlf
      register: _git_verify_autocrlf
      changed_when: false
      failed_when: _git_verify_autocrlf.stdout != 'input'

    # ---- aliases ----

    - name: Check alias.st exists  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get alias.st
      register: _git_verify_alias_st
      changed_when: false
      failed_when: _git_verify_alias_st.stdout != 'status'

    - name: Check alias.lg exists  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get alias.lg
      register: _git_verify_alias_lg
      changed_when: false
      failed_when: _git_verify_alias_lg.rc != 0

    # ---- credential helper ----

    - name: Check credential.helper  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get credential.helper
      register: _git_verify_credential
      changed_when: false
      failed_when: "'cache' not in _git_verify_credential.stdout"

    # ---- git-lfs ----

    - name: Check git-lfs is installed
      ansible.builtin.command:
        cmd: git lfs version
      register: _git_verify_lfs
      changed_when: false
      failed_when: _git_verify_lfs.rc != 0

    # ---- hooks directory ----

    - name: Check hooks directory exists
      ansible.builtin.stat:
        path: /tmp/test-git-hooks
      register: _git_verify_hooks

    - name: Assert hooks directory exists
      ansible.builtin.assert:
        that:
          - _git_verify_hooks.stat.exists
          - _git_verify_hooks.stat.isdir
        fail_msg: "Global hooks directory /tmp/test-git-hooks does not exist"

    # ---- report ----

    - name: Show verify results
      ansible.builtin.debug:
        msg:
          - "All git role checks passed!"
          - "user.name = {{ _git_verify_username.stdout }}"
          - "user.email = {{ _git_verify_email.stdout }}"
          - "init.defaultBranch = {{ _git_verify_branch.stdout }}"
          - "core.editor = {{ _git_verify_editor.stdout }}"
          - "pull.rebase = {{ _git_verify_rebase.stdout }}"
          - "alias.st = {{ _git_verify_alias_st.stdout }}"
          - "credential.helper = {{ _git_verify_credential.stdout }}"
          - "git-lfs = installed"
          - "hooks dir = /tmp/test-git-hooks exists"
```

**Step 4: Commit**

```bash
git add ansible/roles/git/molecule/default/
git commit -m "feat(git): update molecule tests — full coverage for all subsystems (ROLE-006)"
```

---

## Task 12: Run molecule tests on VM

**Step 1: Sync files to VM**

Run: `bash scripts/ssh-scp-to.sh -r ansible/roles/git /home/textyre/bootstrap/ansible/roles/git`

**Step 2: Run molecule converge**

Run (via remote executor):
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg cd ansible/roles/git && molecule converge"
```

Expected: All tasks execute without errors.

**Step 3: Run molecule verify**

Run (via remote executor):
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg cd ansible/roles/git && molecule verify"
```

Expected: All verification checks pass.

**Step 4: Run molecule idempotence**

Run (via remote executor):
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg cd ansible/roles/git && molecule idempotence"
```

Expected: No changed tasks on second run (idempotent).

**Step 5: Fix any failures, re-run, commit fixes**

If any test fails, fix the issue in the relevant task file, sync, and re-run. Commit each fix separately.

---

## Task 13: Wiki documentation

**Files:**
- Create: `wiki/roles/git.md`

**Step 1: Write wiki/roles/git.md**

Create the wiki page covering:
- Role description and purpose
- Variables reference (all sections from defaults/main.yml with descriptions)
- Profile behavior table (base / developer / security)
- Usage examples: basic, signing (SSH), signing (GPG), multi-user, custom aliases, extra config
- Dependencies (none, but designed to complement `user` role)
- Tags reference

**Step 2: Commit**

```bash
git add wiki/roles/git.md
git commit -m "docs(git): add wiki/roles/git.md — variables, profiles, examples (ROLE-006)"
```

---

## Task 14: Final review and cleanup

**Step 1: Delete stale files**

Check if any old files need removal (the original `tasks/main.yml` was replaced, not deleted, so no cleanup needed).

**Step 2: Run full molecule test sequence**

Run: `molecule test` (syntax → converge → idempotence → verify)

Expected: All stages pass.

**Step 3: Run ansible-lint on the role**

Run (via remote executor):
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-lint ansible/roles/git/"
```

Expected: No errors (warnings acceptable for community.general module usage).

**Step 4: Commit any final fixes**

```bash
git commit -m "fix(git): address lint and test findings"
```
