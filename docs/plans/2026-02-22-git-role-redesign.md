# Design: git role redesign

**Date:** 2026-02-22
**Status:** Approved
**Scope:** Full rewrite of `ansible/roles/git/` — compliance with role-requirements.md + full developer toolchain

---

## Context

The current `git` role is minimal: 7 `community.general.git_config` tasks in a single `main.yml` that set global git options for one user. No package installation, no security features, no extensibility.

**Gaps identified:**
- ROLE-001: No `vars/` per-distro, no git installation
- ROLE-003: No `_git_supported_os` list, no preflight assert
- ROLE-005: No `tasks/verify.yml`
- ROLE-006: Molecule tests only check 3 of 7 configured settings
- ROLE-008: No dual logging (no report_phase / report_render)
- ROLE-009: No profile awareness
- ROLE-010: Flat variables, no dict-based config, no overwrite mechanism
- ROLE-011: `community.general.git_config` is FQCN and acceptable (no builtin equivalent)
- No commit signing (GPG or SSH)
- No git aliases
- No credential helper configuration
- No git-lfs support
- No global hooks directory
- No safe.directory (CVE-2022-24765)
- No multi-user support
- No `wiki/roles/git.md`
- `meta/main.yml` only lists Arch Linux

---

## Goals

1. Full compliance with all 11 requirements in `wiki/standards/role-requirements.md`
2. Two-level architecture: system layer (root, once) + per-user layer (become_user, loop)
3. Commit signing via SSH or GPG (selectable per user)
4. Git aliases: preset set + custom via dict
5. Credential helper configuration
6. Git LFS installation and per-user init
7. Global hooks directory
8. Arbitrary git config via dict with overwrite pattern (ROLE-010)
9. Multi-user: owner + additional_users
10. Profile-aware defaults (ROLE-009)
11. Safe directory management (CVE-2022-24765)

---

## Data Model

### Primary owner (`git_owner`)

```yaml
git_owner:
  name: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
  user_name: ""                    # git user.name (empty = skip)
  user_email: ""                   # git user.email (empty = skip)
  signing_method: none             # ssh | gpg | none
  signing_key: ""                  # SSH public key path or GPG key ID
  credential_helper: ""            # per-user override (empty = use git_credential_helper)
```

### Additional users (`git_additional_users`)

```yaml
git_additional_users: []
# - name: alice
#   user_name: "Alice"
#   user_email: "alice@example.com"
#   signing_method: none           # ssh | gpg | none
#   signing_key: ""
#   credential_helper: ""
```

### Shared defaults (applied to all users)

```yaml
git_default_branch: main
git_editor: vim
git_pull_rebase: true
git_push_autosetup_remote: true
git_core_autocrlf: input
git_commit_sign: false             # commit.gpgSign (auto-sign all commits)
```

### Per-subsystem toggles (ROLE-010)

```yaml
git_manage_signing: >-
  {{ true if 'developer' in (workstation_profiles | default([]))
     or 'security' in (workstation_profiles | default([]))
     else false }}
git_manage_aliases: true
git_manage_credential: true
git_manage_hooks: false
git_lfs_enabled: true
```

### Aliases

```yaml
git_aliases_preset:
  st: status
  co: checkout
  br: branch
  ci: commit
  lg: "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
  unstage: "reset HEAD --"
  last: "log -1 HEAD"
  amend: "commit --amend --no-edit"
git_aliases_extra: {}              # user-defined aliases
git_aliases_overwrite: {}          # merge on top of preset + extra
```

### Credential helper

```yaml
git_credential_helper: "cache --timeout=3600"
```

### Global hooks

```yaml
git_hooks_path: "~/.config/git/hooks"
```

### Extra git config (ROLE-010)

```yaml
git_config_extra:
  color.ui: auto
  diff.colorMoved: zebra
  merge.conflictstyle: diff3
  rerere.enabled: "true"
git_config_overwrite: {}           # merge on top of git_config_extra
```

### Safe directory (CVE-2022-24765)

```yaml
git_safe_directories: []           # list of paths for safe.directory
```

### Profile-aware defaults (ROLE-009)

```yaml
# developer: signing and aliases enabled by default
git_manage_signing: >-
  {{ true if 'developer' in (workstation_profiles | default([]))
     or 'security' in (workstation_profiles | default([]))
     else false }}

# security: mandatory commit signing
git_commit_sign: >-
  {{ true if 'security' in (workstation_profiles | default([]))
     else false }}
```

---

## Architecture

### File structure

```
ansible/roles/git/
  defaults/main.yml           # all variables with defaults
  vars/
    archlinux.yml             # _git_packages, _git_lfs_package
    debian.yml
    redhat.yml
    void.yml
    gentoo.yml
  tasks/
    main.yml                  # orchestrator: preflight → system → per-user → verify → report
    # --- System layer (root) ---
    install.yml               # install git + git-lfs (per-distro via vars)
    hooks_global.yml          # create global hooks directory
    # --- Per-user layer (become_user) ---
    configure_user.yml        # dispatcher: calls all per-user task files for one user
    config_base.yml           # user.name, email, defaultBranch, editor, pull.rebase, etc.
    config_extra.yml          # loop over git_config_extra + git_config_overwrite dict
    signing.yml               # SSH or GPG commit signing
    aliases.yml               # preset + custom aliases
    credential.yml            # credential.helper
    lfs_user.yml              # git lfs install --skip-repo (per-user)
    # --- Verification & reporting ---
    verify.yml                # in-role verification (ROLE-005)
  molecule/default/
    molecule.yml
    converge.yml
    verify.yml
  meta/main.yml
wiki/roles/git.md
```

### `tasks/main.yml` flow

```
1. Assert supported OS (ROLE-003)
2. Include OS vars (ROLE-001)
3. Report: preflight passed
4. System: install.yml — install git + git-lfs
5. Report: packages installed
6. System: hooks_global.yml — when git_manage_hooks
7. Per-user: configure_user.yml — loop over [git_owner] + git_additional_users
   ├── config_base.yml
   ├── config_extra.yml
   ├── signing.yml — when git_manage_signing
   ├── aliases.yml — when git_manage_aliases
   ├── credential.yml — when git_manage_credential
   └── lfs_user.yml — when git_lfs_enabled
8. Report: users configured
9. Verify (verify.yml)
10. Report: verification complete
11. Report render (ROLE-008)
```

---

## Key Implementation Patterns

### ROLE-001: OS dispatch

```yaml
# tasks/main.yml
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [git]

# vars/archlinux.yml
_git_packages:
  - git
_git_lfs_package: git-lfs

# vars/debian.yml
_git_packages:
  - git
_git_lfs_package: git-lfs
```

### Per-user loop

```yaml
# tasks/main.yml
- name: Configure git for each user
  ansible.builtin.include_tasks: configure_user.yml
  loop: "{{ [git_owner] + git_additional_users }}"
  loop_control:
    loop_var: _git_current_user
    label: "{{ _git_current_user.name }}"
  tags: [git, configure]
```

### Signing — SSH vs GPG

```yaml
# tasks/signing.yml
- name: Configure SSH commit signing
  when: _git_current_user.signing_method | default('none') == 'ssh'
  become: true
  become_user: "{{ _git_current_user.name }}"
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
  when: _git_current_user.signing_method | default('none') == 'gpg'
  become: true
  become_user: "{{ _git_current_user.name }}"
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

### Aliases — three-layer merge

```yaml
# tasks/aliases.yml
- name: Set git aliases
  become: true
  become_user: "{{ _git_current_user.name }}"
  community.general.git_config:
    name: "alias.{{ item.key }}"
    value: "{{ item.value }}"
    scope: global
  loop: >-
    {{ git_aliases_preset
       | combine(git_aliases_extra)
       | combine(git_aliases_overwrite)
       | dict2items }}
  loop_control:
    label: "{{ item.key }}"
  when: git_manage_aliases | bool
  tags: [git, aliases]
```

### Extra config — dict merge + loop

```yaml
# tasks/config_extra.yml
- name: Set extra git config
  become: true
  become_user: "{{ _git_current_user.name }}"
  community.general.git_config:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    scope: global
  loop: >-
    {{ git_config_extra
       | combine(git_config_overwrite)
       | dict2items }}
  loop_control:
    label: "{{ item.key }}"
  tags: [git, configure]
```

### ROLE-008: Dual logging

```yaml
- name: "Report: git installation"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_phase: "Install git"
    _rpt_detail: >-
      packages={{ _git_packages | join(', ') }}
      lfs={{ git_lfs_enabled }}
  tags: [git, report]

- name: "git -- Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_git_phases"
    _rpt_title: "git"
  tags: [git, report]
```

### ROLE-005: verify.yml

```yaml
# Checks:
# 1. git --version (installed and functional)
# 2. git config --global user.name for owner (when user_name non-empty)
# 3. git config --global commit.gpgSign (when signing enabled)
# 4. git lfs version (when LFS enabled)
# 5. hooks directory exists (when hooks enabled)
# All read-only commands with changed_when: false
```

---

## Molecule Tests

`molecule/default/verify.yml` checks:
1. Git is installed (`git --version` succeeds)
2. Owner `user.name` is set correctly
3. Owner `user.email` is set correctly
4. `init.defaultBranch` is `main`
5. `core.editor` is `vim`
6. `pull.rebase` is `true`
7. `push.autoSetupRemote` is `true`
8. Alias `st` exists (when aliases enabled)
9. `credential.helper` is configured (when credential enabled)
10. `git lfs version` succeeds (when LFS enabled)
11. Hooks directory exists (when hooks enabled)

`molecule/default/molecule.yml`:
- `driver: default`, `managed: false`, localhost
- Test sequence: `syntax`, `converge`, `idempotence`, `verify`
- Test vars: `git_user_name: "Test User"`, `git_user_email: "test@example.com"`

---

## What Is NOT in Scope

- **Git hook files** — role creates directory and sets `core.hooksPath`, does not deploy hook scripts (dotfiles/chezmoi)
- **GPG key import** — role configures git to use a GPG key, does not import it
- **SSH key generation** — managed by `user` role
- **Git completion/prompt** — managed by shell/dotfiles
- **Per-repository config** — global scope only
- **Git daemon/server** — not workstation scope
- **Includeif/conditional includes** — achievable via `git_config_extra`, not a dedicated feature
- **Password/token storage in vault** — credential helper manages caching; actual tokens are out of scope

---

## Wiki Documentation

New file: `wiki/roles/git.md` — covers:
- Variables reference (all sections from data model)
- Profile behavior table (developer / security / base)
- Signing setup examples (SSH and GPG)
- Multi-user configuration example
- Aliases customization example
- Integration with user role (git_owner.name should match user_owner.name)
