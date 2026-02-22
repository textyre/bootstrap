# Design: user role redesign

**Date:** 2026-02-22
**Status:** Approved
**Scope:** Full rewrite of `ansible/roles/user/` — compliance with role-requirements.md + feature expansion

---

## Context

The current `user` role covers: sudo install, user creation, sudoers hardening, sudo logrotate.

**Gaps identified:**
- ROLE-001: No `vars/` per-distro, only 2 of 5 OS install stubs
- ROLE-003: No `_user_supported_os` list, no preflight assert
- ROLE-005: No `tasks/verify.yml`
- ROLE-008: Uses raw `debug` instead of `common/report_phase.yml` + `report_render.yml`
- ROLE-011: `install-archlinux.yml` uses `community.general.pacman`, not `ansible.builtin.package`
- No SSH authorized_keys management
- No password-via-vault support
- No password aging (CIS 5.5.x)
- No umask management (CIS 5.4.x)
- No root account verification (CIS 5.4.x)
- No profile-aware sudo defaults
- Only one user; no support for additional users (family accounts, etc.)
- No `wiki/roles/user.md`

---

## Goals

1. Full compliance with all 11 requirements in `wiki/standards/role-requirements.md`
2. Support one primary owner user + optional list of additional users
3. SSH authorized_keys management
4. Password via ansible-vault (secure, idempotent)
5. Password aging: `password_expire_max/min` via `ansible.builtin.user` module params
6. Per-user umask via shell profile
7. Root account lock verification
8. Profile-aware sudo defaults (`developer` / `security` profiles)

---

## Data Model

### Primary owner (`user_owner`)

```yaml
user_owner:
  name: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
  shell: /bin/bash
  groups: [wheel]
  password_hash: ""              # vault: vault_owner_password_hash (sha512 pre-hashed)
  update_password: on_create     # idempotent: don't re-hash on every run
  ssh_keys: []                   # list of public key strings
  umask: "027"                   # CIS 5.4.x
  password_max_age: 365          # CIS 5.5.x
  password_min_age: 1
  password_warn_age: 7
```

### Additional users (`user_additional_users`)

```yaml
user_additional_users: []
# - name: alice
#   shell: /bin/bash
#   groups: [video, audio]
#   sudo: false                  # if true: added to user_sudo_group
#   password_hash: "{{ vault_alice_password }}"
#   update_password: on_create
#   ssh_keys: []
#   umask: "077"
#   password_max_age: 90
#   password_min_age: 0
```

### Feature toggles

```yaml
user_manage_ssh_keys: true
user_manage_password_aging: true
user_manage_umask: true
user_verify_root_lock: true      # CIS 5.4.x
```

### Global sudo policy

```yaml
user_sudo_group: "{{ 'wheel' if ansible_facts['os_family'] == 'Archlinux' else 'sudo' }}"
user_sudo_timestamp_timeout: >-
  {{ 15 if 'developer' in (workstation_profiles | default([]))
     else 0 if 'security' in (workstation_profiles | default([]))
     else 5 }}
user_sudo_use_pty: true
user_sudo_logfile: /var/log/sudo.log
user_sudo_passwd_timeout: 1
user_sudo_logrotate_enabled: true
user_sudo_logrotate_rotate: 13
```

---

## Architecture

### File structure

```
ansible/roles/user/
  defaults/main.yml
  vars/
    archlinux.yml      # _user_packages: [sudo]
    debian.yml
    redhat.yml
    void.yml
    gentoo.yml
  tasks/
    main.yml           # preflight → install → owner → additional_users → sudo → verify → report
    install-archlinux.yml
    install-debian.yml
    install-redhat.yml
    install-void.yml
    install-gentoo.yml
    owner.yml          # create owner + ssh_keys + umask + password aging
    additional_users.yml  # loop over user_additional_users
    sudo.yml           # sudoers_hardening.j2 + logrotate
    security.yml       # root lock verification (CIS 5.4.x)
    verify.yml         # lineinfile check_mode + getent + assert
  templates/
    sudoers_hardening.j2   # existing, keep
    sudo_logrotate.j2      # existing, keep
    user_umask.sh.j2       # new: /etc/profile.d/user-umask.sh
  molecule/default/
    molecule.yml
    converge.yml
    verify.yml
  meta/main.yml
wiki/roles/user.md
```

### `tasks/main.yml` flow

```
1. Assert supported OS (ROLE-003)
2. Include vars (OS-specific packages)
3. Install sudo (OS dispatch)
4. Create/configure owner user (owner.yml)
5. Create/configure additional users (additional_users.yml) — when list non-empty
6. Deploy sudo policy (sudo.yml)
7. Verify root account lock (security.yml) — when user_verify_root_lock
8. Run in-role verification (verify.yml)
9. Report phases (report_phase + report_render)
```

---

## Key Implementation Patterns

### ROLE-001: OS dispatch
```yaml
# tasks/main.yml
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"

- name: Install sudo (OS-specific)
  ansible.builtin.include_tasks: "install-{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [user, sudo, install]

# vars/archlinux.yml
_user_packages:
  - sudo
```

### ROLE-011: ansible.builtin.package only
```yaml
# tasks/install-archlinux.yml (and all others)
- name: Ensure sudo is installed
  ansible.builtin.package:
    name: "{{ _user_packages }}"
    state: present
  tags: [user, sudo, install]
```

### SSH keys — with_subelements
```yaml
- name: Add SSH authorized keys
  ansible.posix.authorized_key:
    user: "{{ item.0.name }}"
    key: "{{ item.1 }}"
    manage_dir: true
    state: present
  with_subelements:
    - "{{ [user_owner] + user_additional_users }}"
    - ssh_keys
    - skip_missing: true
  no_log: true
  when: user_manage_ssh_keys | bool
  tags: [user, ssh]
```

### Password — idempotent, secure
```yaml
- name: Set user password and aging
  ansible.builtin.user:
    name: "{{ item.name }}"
    password: "{{ item.password_hash | default(omit) }}"
    update_password: "{{ item.update_password | default('on_create') }}"
    password_expire_max: "{{ item.password_max_age | default(omit) }}"
    password_expire_min: "{{ item.password_min_age | default(omit) }}"
  no_log: true
  when: user_manage_password_aging | bool
  tags: [user, security, cis_5.5]
```

### Profile-aware sudo (ROLE-009)
```yaml
# defaults/main.yml
user_sudo_timestamp_timeout: >-
  {{ 15 if 'developer' in (workstation_profiles | default([]))
     else 0 if 'security' in (workstation_profiles | default([]))
     else 5 }}
```

### ROLE-008: Dual logging
```yaml
- name: "Report: user configuration"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_phase: "Configure users"
    _rpt_detail: >-
      owner={{ user_owner.name }}
      additional={{ user_additional_users | length }}
      sudo_group={{ user_sudo_group }}

- name: "user -- Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_title: "user"
  tags: [user, report]
```

### ROLE-005: verify.yml
```yaml
- name: Verify owner user exists
  ansible.builtin.getent:
    database: passwd
    key: "{{ user_owner.name }}"
  register: _user_verify_owner
  failed_when: _user_verify_owner is failed
  tags: [user]

- name: Verify sudoers file syntax
  ansible.builtin.command:
    cmd: "/usr/sbin/visudo -cf /etc/sudoers.d/{{ user_sudo_group }}"
  register: _user_verify_sudoers
  changed_when: false
  failed_when: _user_verify_sudoers.rc != 0
  tags: [user]

- name: Assert owner is in sudo group
  ansible.builtin.command:
    cmd: "groups {{ user_owner.name }}"
  register: _user_verify_groups
  changed_when: false
  failed_when: user_sudo_group not in _user_verify_groups.stdout
  when: user_owner.groups is defined and user_sudo_group in user_owner.groups
  tags: [user]
```

---

## Security Controls (CIS / ROLE-004)

| CIS ID | What | Task tag |
|--------|------|----------|
| CIS 5.3.4 | sudo timestamp_timeout ≤ 5 min | `cis_5.3.4` |
| CIS 5.3.5 | sudo use_pty | `cis_5.3.5` |
| CIS 5.3.7 | sudo logfile | `cis_5.3.7` |
| CIS 5.4.2 | umask 027 for users | `cis_5.4.2` |
| CIS 5.4.3 | root account: no direct login | `cis_5.4.3` |
| CIS 5.5.1 | password_expire_max ≤ 365 | `cis_5.5.1` |
| CIS 5.5.2 | password_expire_min ≥ 1 | `cis_5.5.2` |

---

## Molecule Tests

`molecule/default/verify.yml` checks:
1. Owner user exists in `/etc/passwd`
2. Owner is in `wheel` group
3. `/etc/sudoers.d/wheel` exists and passes `visudo -cf`
4. `user_sudo_timestamp_timeout` is in sudoers file
5. `use_pty` is in sudoers file (when enabled)
6. Logrotate config exists when `user_sudo_logrotate_enabled`

---

## What Is NOT in Scope

- Home directory dotfiles (handled by `dotfiles` role / chezmoi)
- PAM configuration (handled by `pam_hardening` role)
- SSH server configuration (handled by `ssh` role)
- Password auto-generation (YAGNI — vault-managed passwords only)

---

## Wiki Documentation

New file: `wiki/roles/user.md` — covers:
- Variables reference
- Profile behavior table (developer / security / base)
- Vault integration example
- SSH key setup example
- Additional users example
