# user role redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fully rewrite the `ansible/roles/user/` role to comply with all 11 role requirements and add multi-user support, SSH key management, vault passwords, password aging, umask, and profile-aware sudo.

**Architecture:** Primary owner (`user_owner: {}`) + optional additional users (`user_additional_users: []`). Global sudo policy via `user_sudo_*` vars. All user creation/SSH/aging handled via `ansible.builtin.user` + `ansible.posix.authorized_key` loops. Profile-aware defaults via `workstation_profiles`.

**Design doc:** `docs/plans/2026-02-22-user-role-redesign.md`

**Tech Stack:** Ansible 2.15+, `ansible.builtin.*` only for installs, `ansible.posix.authorized_key` for SSH keys, `common` role for reporting.

**Testing:** All molecule runs via `bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule <cmd> -s default"` from `ansible/roles/user/`.

---

### Task 1: Rewrite `defaults/main.yml` — new data model

**Files:**
- Modify: `ansible/roles/user/defaults/main.yml`

**Step 1: Replace the entire defaults file**

```yaml
---
# === user role — defaults ===

# --- ROLE-003: Supported operating systems ---
_user_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# --- Primary owner (always one, admin of the machine) ---
user_owner:
  name: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
  shell: /bin/bash
  groups:
    - wheel
  password_hash: ""             # Pre-hashed sha512. Set via vault: vault_owner_password_hash
  update_password: on_create    # Don't re-hash on every run (idempotent)
  ssh_keys: []                  # List of public key strings
  umask: "027"                  # CIS 5.4.2: restrictive default umask
  password_max_age: 365         # CIS 5.5.1: days before password must change
  password_min_age: 1           # CIS 5.5.2: days before password can change
  password_warn_age: 7          # Days before expiry to warn

# --- Additional users (family, guests, etc.) ---
# Each entry supports the same fields as user_owner, plus:
#   sudo: true/false  — whether to add to user_sudo_group
user_additional_users: []
# Example:
# user_additional_users:
#   - name: alice
#     shell: /bin/bash
#     groups: [video, audio]
#     sudo: false
#     password_hash: "{{ vault_alice_password }}"
#     update_password: on_create
#     ssh_keys: []
#     umask: "077"
#     password_max_age: 90
#     password_min_age: 0
#     password_warn_age: 7

# --- Feature toggles ---
user_manage_ssh_keys: true        # Manage ~/.ssh/authorized_keys
user_manage_password_aging: true  # Set password_expire_max/min
user_manage_umask: true           # Deploy /etc/profile.d/umask for each user
user_verify_root_lock: true       # CIS 5.4.3: assert root has no direct password login

# --- Global sudo policy ---
# sudo group name: wheel on Arch, sudo on Debian/Ubuntu
user_sudo_group: "{{ 'wheel' if ansible_facts['os_family'] == 'Archlinux' else 'sudo' }}"

# timestamp_timeout: profile-aware
# developer profile → 15 min (comfortable for development)
# security profile  → 0 min (re-enter password every time)
# default           → 5 min (CIS 5.3.4: must be <= 5)
user_sudo_timestamp_timeout: >-
  {{ 0 if 'security' in (workstation_profiles | default([]))
     else 15 if 'developer' in (workstation_profiles | default([]))
     else 5 }}

user_sudo_use_pty: true                # CIS 5.3.5: prevent PTY injection
user_sudo_logfile: "/var/log/sudo.log" # CIS 5.3.7: audit trail
user_sudo_log_input: false             # Record stdin of sudo sessions
user_sudo_log_output: false            # Record stdout/stderr of sudo sessions
user_sudo_passwd_timeout: 1            # Minutes to enter password

# Logrotate for sudo.log
user_sudo_logrotate_enabled: true
user_sudo_logrotate_frequency: "weekly"
user_sudo_logrotate_rotate: 13         # 13 weeks ≈ 90 days (CIS minimum retention)
```

**Step 2: Commit**

```bash
git add ansible/roles/user/defaults/main.yml
git commit -m "feat(user): rewrite defaults — user_owner/user_additional_users data model"
```

---

### Task 2: Create `vars/` per-distro (ROLE-001)

**Files:**
- Create: `ansible/roles/user/vars/archlinux.yml`
- Create: `ansible/roles/user/vars/debian.yml`
- Create: `ansible/roles/user/vars/redhat.yml`
- Create: `ansible/roles/user/vars/void.yml`
- Create: `ansible/roles/user/vars/gentoo.yml`

**Step 1: Create all five vars files**

`ansible/roles/user/vars/archlinux.yml`:
```yaml
---
_user_packages:
  - sudo
```

`ansible/roles/user/vars/debian.yml`:
```yaml
---
_user_packages:
  - sudo
```

`ansible/roles/user/vars/redhat.yml`:
```yaml
---
_user_packages:
  - sudo
```

`ansible/roles/user/vars/void.yml`:
```yaml
---
_user_packages:
  - sudo
```

`ansible/roles/user/vars/gentoo.yml`:
```yaml
---
_user_packages:
  - app-admin/sudo
```

**Step 2: Commit**

```bash
git add ansible/roles/user/vars/
git commit -m "feat(user): add per-distro vars files (ROLE-001)"
```

---

### Task 3: Fix install tasks — use `ansible.builtin.package` (ROLE-011)

**Files:**
- Modify: `ansible/roles/user/tasks/install-archlinux.yml`
- Modify: `ansible/roles/user/tasks/install-debian.yml`
- Create: `ansible/roles/user/tasks/install-redhat.yml`
- Create: `ansible/roles/user/tasks/install-void.yml`
- Create: `ansible/roles/user/tasks/install-gentoo.yml`

**Step 1: Rewrite `install-archlinux.yml`**

```yaml
---
# === Arch Linux: install sudo ===
- name: Ensure sudo is installed
  ansible.builtin.package:
    name: "{{ _user_packages }}"
    state: present
  tags: [user, sudo, install]
```

**Step 2: Rewrite `install-debian.yml`**

```yaml
---
# === Debian/Ubuntu: install sudo ===
- name: Ensure sudo is installed
  ansible.builtin.package:
    name: "{{ _user_packages }}"
    state: present
  tags: [user, sudo, install]
```

**Step 3: Create `install-redhat.yml`**

```yaml
---
# === Fedora/RedHat: install sudo ===
- name: Ensure sudo is installed
  ansible.builtin.package:
    name: "{{ _user_packages }}"
    state: present
  tags: [user, sudo, install]
```

**Step 4: Create `install-void.yml`**

```yaml
---
# === Void Linux: install sudo ===
- name: Ensure sudo is installed
  ansible.builtin.package:
    name: "{{ _user_packages }}"
    state: present
  tags: [user, sudo, install]
```

**Step 5: Create `install-gentoo.yml`**

```yaml
---
# === Gentoo: install sudo ===
- name: Ensure sudo is installed
  ansible.builtin.package:
    name: "{{ _user_packages }}"
    state: present
  tags: [user, sudo, install]
```

**Step 6: Commit**

```bash
git add ansible/roles/user/tasks/install-*.yml
git commit -m "fix(user): use ansible.builtin.package in all install tasks (ROLE-011)"
```

---

### Task 4: Create `tasks/owner.yml` — owner user creation + password aging + umask

**Files:**
- Create: `ansible/roles/user/tasks/owner.yml`
- Create: `ansible/roles/user/templates/user_umask.sh.j2`

**Step 1: Create `templates/user_umask.sh.j2`**

```bash
# {{ ansible_managed }}
# Per-user umask — set by ansible/roles/user
# Applied at login for {{ _umask_user }}
if [ "$(id -nu)" = "{{ _umask_user }}" ]; then
    umask {{ _umask_value }}
fi
```

**Step 2: Create `tasks/owner.yml`**

```yaml
---
# === Create and configure the primary owner user ===

- name: "CIS 5.x | Ensure owner user exists"
  ansible.builtin.user:
    name: "{{ user_owner.name }}"
    shell: "{{ user_owner.shell | default('/bin/bash') }}"
    groups: "{{ user_owner.groups | default(['wheel']) }}"
    append: true
    create_home: true
    password: "{{ user_owner.password_hash | default(omit) }}"
    update_password: "{{ user_owner.update_password | default('on_create') }}"
    password_expire_max: >-
      {{ user_owner.password_max_age | default(omit)
         if user_manage_password_aging | bool else omit }}
    password_expire_min: >-
      {{ user_owner.password_min_age | default(omit)
         if user_manage_password_aging | bool else omit }}
  no_log: true
  tags: [user, cis_5.5.1, cis_5.5.2]

- name: "CIS 5.4.2 | Deploy umask profile for owner"
  ansible.builtin.template:
    src: user_umask.sh.j2
    dest: "/etc/profile.d/umask-{{ user_owner.name }}.sh"
    owner: root
    group: root
    mode: "0644"
  vars:
    _umask_user: "{{ user_owner.name }}"
    _umask_value: "{{ user_owner.umask | default('027') }}"
  when: user_manage_umask | bool
  tags: [user, cis_5.4.2]
```

**Step 3: Commit**

```bash
git add ansible/roles/user/tasks/owner.yml ansible/roles/user/templates/user_umask.sh.j2
git commit -m "feat(user): add owner.yml — user creation, password aging, umask (CIS 5.4, 5.5)"
```

---

### Task 5: Create `tasks/additional_users.yml` — loop over extra users

**Files:**
- Create: `ansible/roles/user/tasks/additional_users.yml`

**Step 1: Create `tasks/additional_users.yml`**

```yaml
---
# === Create and configure additional (non-owner) users ===
# Each user in user_additional_users gets: account, optional sudo, umask

- name: "Ensure additional users exist"
  ansible.builtin.user:
    name: "{{ item.name }}"
    shell: "{{ item.shell | default('/bin/bash') }}"
    groups: "{{ item.groups | default([]) }}"
    append: true
    create_home: true
    password: "{{ item.password_hash | default(omit) }}"
    update_password: "{{ item.update_password | default('on_create') }}"
    password_expire_max: >-
      {{ item.password_max_age | default(omit)
         if user_manage_password_aging | bool else omit }}
    password_expire_min: >-
      {{ item.password_min_age | default(omit)
         if user_manage_password_aging | bool else omit }}
  loop: "{{ user_additional_users }}"
  no_log: true
  when: user_additional_users | length > 0
  tags: [user, cis_5.5.1, cis_5.5.2]

- name: "Add additional users to sudo group when sudo: true"
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ user_sudo_group }}"
    append: true
  loop: "{{ user_additional_users }}"
  when:
    - user_additional_users | length > 0
    - item.sudo | default(false) | bool
  tags: [user, sudo]

- name: "CIS 5.4.2 | Deploy umask profile for additional users"
  ansible.builtin.template:
    src: user_umask.sh.j2
    dest: "/etc/profile.d/umask-{{ item.name }}.sh"
    owner: root
    group: root
    mode: "0644"
  vars:
    _umask_user: "{{ item.name }}"
    _umask_value: "{{ item.umask | default('077') }}"
  loop: "{{ user_additional_users }}"
  when:
    - user_manage_umask | bool
    - user_additional_users | length > 0
  tags: [user, cis_5.4.2]
```

**Step 2: Commit**

```bash
git add ansible/roles/user/tasks/additional_users.yml
git commit -m "feat(user): add additional_users.yml — multi-user loop support"
```

---

### Task 6: SSH authorized_keys management

**Files:**
- Create: `ansible/roles/user/tasks/ssh_keys.yml`

**Step 1: Check that `ansible.posix` collection is available**

Run on VM:
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-galaxy collection list | grep ansible.posix"
```

Expected output: line containing `ansible.posix` and a version. If missing, the collection needs installing (check `ansible/requirements.yml`).

**Step 2: Create `tasks/ssh_keys.yml`**

```yaml
---
# === SSH authorized_keys management ===
# Uses with_subelements to iterate over users × ssh_keys pairs.
# skip_missing: true — users without ssh_keys are silently skipped.

- name: "Ensure .ssh directory exists for all managed users"
  ansible.builtin.file:
    path: "{{ '/root' if item.name == 'root' else '/home/' + item.name }}/.ssh"
    state: directory
    owner: "{{ item.name }}"
    mode: "0700"
  loop: "{{ [user_owner] + user_additional_users }}"
  when:
    - user_manage_ssh_keys | bool
    - item.ssh_keys is defined
    - item.ssh_keys | length > 0
  tags: [user, ssh]

- name: "Add SSH authorized keys"
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

**Step 3: Commit**

```bash
git add ansible/roles/user/tasks/ssh_keys.yml
git commit -m "feat(user): add SSH authorized_keys management (ansible.posix)"
```

---

### Task 7: Rewrite `tasks/sudo.yml` — profile-aware sudoers

The existing `main.yml` inline sudo tasks need to move into a dedicated file, and the sudoers template already handles profile-aware timeout via the variable. No template changes needed.

**Files:**
- Create: `ansible/roles/user/tasks/sudo.yml`

**Step 1: Create `tasks/sudo.yml`**

```yaml
---
# === Deploy sudo policy ===

- name: "CIS 5.3.4/5.3.5/5.3.7 | Deploy sudoers hardening"
  ansible.builtin.template:
    src: sudoers_hardening.j2
    dest: "/etc/sudoers.d/{{ user_sudo_group }}"
    owner: root
    group: root
    mode: "0440"
    validate: "/usr/sbin/visudo -cf %s"
  tags: [user, sudo, security, cis_5.3.4, cis_5.3.5, cis_5.3.7]

- name: "Configure logrotate for sudo.log"
  ansible.builtin.template:
    src: sudo_logrotate.j2
    dest: /etc/logrotate.d/sudo
    owner: root
    group: root
    mode: "0644"
  when:
    - user_sudo_logrotate_enabled | bool
    - user_sudo_logfile | length > 0
  tags: [user, sudo, security]
```

**Step 2: Commit**

```bash
git add ansible/roles/user/tasks/sudo.yml
git commit -m "refactor(user): extract sudo tasks to tasks/sudo.yml"
```

---

### Task 8: Create `tasks/security.yml` — root account verification

**Files:**
- Create: `ansible/roles/user/tasks/security.yml`

**Step 1: Create `tasks/security.yml`**

```yaml
---
# === Security checks — CIS 5.4.3: root account ===

- name: "CIS 5.4.3 | Get root account passwd entry"
  ansible.builtin.getent:
    database: passwd
    key: root
  register: _user_root_entry
  changed_when: false
  tags: [user, security, cis_5.4.3]

- name: "CIS 5.4.3 | Get root account shadow entry"
  ansible.builtin.getent:
    database: shadow
    key: root
  register: _user_root_shadow
  changed_when: false
  no_log: true
  tags: [user, security, cis_5.4.3]

- name: "CIS 5.4.3 | Assert root password is locked or empty"
  ansible.builtin.assert:
    that:
      # Shadow password field starts with ! (locked) or * (no password)
      - _user_root_shadow.ansible_facts.getent_shadow['root'][0] in ['!', '*', '!*', '!!']
        or _user_root_shadow.ansible_facts.getent_shadow['root'][0] | regex_search('^[!*]')
    fail_msg: >-
      CIS 5.4.3 FAIL: root account has a usable password.
      Direct root login must be disabled. Use sudo for privilege escalation.
    success_msg: "CIS 5.4.3 PASS: root account is locked"
  when: user_verify_root_lock | bool
  tags: [user, security, cis_5.4.3]
```

**Step 2: Commit**

```bash
git add ansible/roles/user/tasks/security.yml
git commit -m "feat(user): add security.yml — root account lock verification (CIS 5.4.3)"
```

---

### Task 9: Create `tasks/verify.yml` — in-role verification (ROLE-005)

**Files:**
- Create: `ansible/roles/user/tasks/verify.yml`

**Step 1: Create `tasks/verify.yml`**

```yaml
---
# === In-role verification (ROLE-005) ===
# Uses check_mode + assertions — never modifies state.

- name: "Verify owner user exists in passwd"
  ansible.builtin.getent:
    database: passwd
    key: "{{ user_owner.name }}"
  register: _user_verify_owner
  failed_when: _user_verify_owner is failed
  changed_when: false
  tags: [user]

- name: "Verify owner is in sudo group"
  ansible.builtin.command:
    cmd: "groups {{ user_owner.name }}"
  register: _user_verify_groups
  changed_when: false
  failed_when: user_sudo_group not in _user_verify_groups.stdout
  when: user_sudo_group in (user_owner.groups | default([]))
  tags: [user]

- name: "Verify sudoers.d file exists"
  ansible.builtin.stat:
    path: "/etc/sudoers.d/{{ user_sudo_group }}"
  register: _user_verify_sudoers_stat
  failed_when: not _user_verify_sudoers_stat.stat.exists
  tags: [user]

- name: "Verify sudoers file syntax"
  ansible.builtin.command:
    cmd: "/usr/sbin/visudo -cf /etc/sudoers.d/{{ user_sudo_group }}"
  register: _user_verify_sudoers_syntax
  changed_when: false
  failed_when: _user_verify_sudoers_syntax.rc != 0
  tags: [user]

- name: "Verify umask profile deployed for owner"
  ansible.builtin.stat:
    path: "/etc/profile.d/umask-{{ user_owner.name }}.sh"
  register: _user_verify_umask
  failed_when: not _user_verify_umask.stat.exists
  when: user_manage_umask | bool
  tags: [user]
```

**Step 2: Commit**

```bash
git add ansible/roles/user/tasks/verify.yml
git commit -m "feat(user): add verify.yml — in-role verification (ROLE-005)"
```

---

### Task 10: Rewrite `tasks/main.yml` — wire everything together (ROLE-003, ROLE-008)

**Files:**
- Modify: `ansible/roles/user/tasks/main.yml`

**Step 1: Rewrite `tasks/main.yml`**

```yaml
---
# === user role — main orchestration ===

# ROLE-003: Preflight — fail fast on unsupported OS
- name: "Assert supported operating system"
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] in _user_supported_os
    fail_msg: >-
      OS family '{{ ansible_facts['os_family'] }}' is not supported.
      Supported: {{ _user_supported_os | join(', ') }}
    success_msg: "OS family '{{ ansible_facts['os_family'] }}' is supported"
  tags: [user]

# ROLE-001: Load OS-specific variables
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [user]

# Install sudo
- name: Install sudo (OS-specific)
  ansible.builtin.include_tasks: "install-{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [user, sudo, install]

# ROLE-008: Report install phase
- name: "Report: sudo install"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_phase: "Install"
    _rpt_detail: "sudo installed via {{ ansible_facts['os_family'] | lower }} package manager"
  tags: [user, report]

# Create and configure owner
- name: Configure owner user
  ansible.builtin.include_tasks: owner.yml
  tags: [user]

# ROLE-008: Report owner phase
- name: "Report: owner configuration"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_phase: "Owner"
    _rpt_detail: >-
      user={{ user_owner.name }}
      shell={{ user_owner.shell | default('/bin/bash') }}
      groups={{ user_owner.groups | default(['wheel']) | join(',') }}
  tags: [user, report]

# Create additional users (when list is non-empty)
- name: Configure additional users
  ansible.builtin.include_tasks: additional_users.yml
  when: user_additional_users | length > 0
  tags: [user]

# ROLE-008: Report additional users phase
- name: "Report: additional users"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_phase: "Additional users"
    _rpt_detail: "count={{ user_additional_users | length }}"
  tags: [user, report]

# SSH keys
- name: Manage SSH authorized keys
  ansible.builtin.include_tasks: ssh_keys.yml
  when: user_manage_ssh_keys | bool
  tags: [user, ssh]

# Deploy sudo policy
- name: Deploy sudo policy
  ansible.builtin.include_tasks: sudo.yml
  tags: [user, sudo]

# ROLE-008: Report sudo phase
- name: "Report: sudo policy"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_phase: "Sudo policy"
    _rpt_detail: >-
      group={{ user_sudo_group }}
      timeout={{ user_sudo_timestamp_timeout }}
      pty={{ user_sudo_use_pty }}
  tags: [user, report]

# CIS security checks
- name: Security verification
  ansible.builtin.include_tasks: security.yml
  when: user_verify_root_lock | bool
  tags: [user, security]

# ROLE-005: In-role verification
- name: Verify user configuration
  ansible.builtin.include_tasks: verify.yml
  tags: [user]

# ROLE-008: Final report render
- name: "user -- Execution Report"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_render.yml
  vars:
    _rpt_fact: "_user_phases"
    _rpt_title: "user"
  tags: [user, report]
```

**Step 2: Commit**

```bash
git add ansible/roles/user/tasks/main.yml
git commit -m "refactor(user): rewrite main.yml — ROLE-003 preflight, ROLE-008 dual logging, full task wiring"
```

---

### Task 11: Update molecule tests (ROLE-006)

**Files:**
- Modify: `ansible/roles/user/molecule/default/converge.yml`
- Modify: `ansible/roles/user/molecule/default/verify.yml`
- Modify: `ansible/roles/user/molecule/default/molecule.yml`

**Step 1: Update `converge.yml`**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  pre_tasks:
    - name: Assert test environment is Arch Linux
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] == 'Archlinux'
        fail_msg: "This test requires Arch Linux"

  vars:
    # Override owner to a test user so we don't modify the actual running user
    user_owner:
      name: testuser_owner
      shell: /bin/bash
      groups: [wheel]
      password_hash: ""
      update_password: on_create
      ssh_keys:
        - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBDummyKeyForTestingPurposesOnly testuser@molecule"
      umask: "027"
      password_max_age: 365
      password_min_age: 1
      password_warn_age: 7
    user_additional_users:
      - name: testuser_extra
        shell: /bin/bash
        groups: [video]
        sudo: false
        password_hash: ""
        update_password: on_create
        ssh_keys: []
        umask: "077"
    user_manage_ssh_keys: true
    user_manage_password_aging: false   # skip aging in container (may not be supported)
    user_manage_umask: true
    user_verify_root_lock: false        # root may not be locked in test container

  roles:
    - role: user
```

**Step 2: Update `verify.yml`**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true

  tasks:
    # --- Owner user ---
    - name: Check owner user exists
      ansible.builtin.getent:
        database: passwd
        key: testuser_owner
      register: _user_verify_owner
      failed_when: _user_verify_owner is failed

    - name: Check owner is in wheel group
      ansible.builtin.command:
        cmd: groups testuser_owner
      register: _user_verify_owner_groups
      changed_when: false
      failed_when: "'wheel' not in _user_verify_owner_groups.stdout"

    - name: Check owner umask profile deployed
      ansible.builtin.stat:
        path: /etc/profile.d/umask-testuser_owner.sh
      register: _user_verify_umask
      failed_when: not _user_verify_umask.stat.exists

    - name: Check owner umask value in profile
      ansible.builtin.command:
        cmd: grep -q "umask 027" /etc/profile.d/umask-testuser_owner.sh
      changed_when: false
      failed_when: false  # non-zero means grep found nothing → will be caught by next assert
      register: _user_verify_umask_value

    - name: Assert owner umask is 027
      ansible.builtin.assert:
        that: _user_verify_umask_value.rc == 0
        fail_msg: "Owner umask profile does not contain 'umask 027'"

    # --- SSH keys ---
    - name: Check authorized_keys file exists for owner
      ansible.builtin.stat:
        path: /home/testuser_owner/.ssh/authorized_keys
      register: _user_verify_ssh
      failed_when: not _user_verify_ssh.stat.exists

    - name: Check SSH key content
      ansible.builtin.command:
        cmd: grep -q "testuser@molecule" /home/testuser_owner/.ssh/authorized_keys
      changed_when: false
      register: _user_verify_ssh_key
      failed_when: _user_verify_ssh_key.rc != 0

    # --- Additional user ---
    - name: Check extra user exists
      ansible.builtin.getent:
        database: passwd
        key: testuser_extra
      register: _user_verify_extra
      failed_when: _user_verify_extra is failed

    - name: Check extra user is NOT in wheel group
      ansible.builtin.command:
        cmd: groups testuser_extra
      register: _user_verify_extra_groups
      changed_when: false
      failed_when: "'wheel' in _user_verify_extra_groups.stdout"

    # --- Sudo policy ---
    - name: Check sudoers.d/wheel exists
      ansible.builtin.stat:
        path: /etc/sudoers.d/wheel
      register: _user_verify_sudoers
      failed_when: not _user_verify_sudoers.stat.exists

    - name: Validate sudoers.d/wheel syntax
      ansible.builtin.command:
        cmd: /usr/sbin/visudo -cf /etc/sudoers.d/wheel
      register: _user_verify_sudoers_syntax
      changed_when: false
      failed_when: _user_verify_sudoers_syntax.rc != 0

    - name: Check use_pty in sudoers
      ansible.builtin.command:
        cmd: grep -q "use_pty" /etc/sudoers.d/wheel
      changed_when: false
      register: _user_verify_pty
      failed_when: _user_verify_pty.rc != 0

    - name: Check logfile in sudoers
      ansible.builtin.command:
        cmd: grep -q "logfile" /etc/sudoers.d/wheel
      changed_when: false
      register: _user_verify_logfile
      failed_when: _user_verify_logfile.rc != 0

    - name: Show test results
      ansible.builtin.debug:
        msg: "All user role checks passed!"
```

**Step 3: Run molecule to verify everything passes**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/user && source ../../.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule test -s default"
```

Expected: all tasks PASSED, no failures.

**Step 4: Commit**

```bash
git add ansible/roles/user/molecule/
git commit -m "test(user): update molecule tests — multi-user, SSH keys, umask verification (ROLE-006)"
```

---

### Task 12: Update `meta/main.yml`

**Files:**
- Modify: `ansible/roles/user/meta/main.yml`

**Step 1: Update meta to list all 5 distros**

```yaml
---
galaxy_info:
  role_name: user
  author: textyre
  description: >-
    User account lifecycle management: owner user, additional users, sudo hardening,
    SSH authorized keys, password aging, umask. CIS Level 1 Workstation compliant.
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
  galaxy_tags: [user, sudo, ssh, groups, cis, hardening]
dependencies: []
```

**Step 2: Commit**

```bash
git add ansible/roles/user/meta/main.yml
git commit -m "chore(user): update meta — all 5 distros, updated description"
```

---

### Task 13: Create `wiki/roles/user.md`

**Files:**
- Create: `wiki/roles/user.md`

**Step 1: Create the wiki doc**

```markdown
# user role

Manages user accounts on workstations: primary owner user, optional additional users,
sudo hardening, SSH authorized keys, password aging, and umask configuration.

## Variables

### Owner user

| Variable | Default | Description |
|----------|---------|-------------|
| `user_owner.name` | `SUDO_USER` or current user | Primary admin user |
| `user_owner.shell` | `/bin/bash` | Login shell |
| `user_owner.groups` | `[wheel]` | Supplementary groups |
| `user_owner.password_hash` | `""` | Pre-hashed sha512 from vault |
| `user_owner.update_password` | `on_create` | `always` or `on_create` |
| `user_owner.ssh_keys` | `[]` | List of public key strings |
| `user_owner.umask` | `"027"` | CIS 5.4.2 login umask |
| `user_owner.password_max_age` | `365` | CIS 5.5.1 — days before must change |
| `user_owner.password_min_age` | `1` | CIS 5.5.2 — days before can change |

### Feature toggles

| Variable | Default | Description |
|----------|---------|-------------|
| `user_manage_ssh_keys` | `true` | Manage ~/.ssh/authorized_keys |
| `user_manage_password_aging` | `true` | Apply password_expire_max/min |
| `user_manage_umask` | `true` | Deploy /etc/profile.d/umask-<user>.sh |
| `user_verify_root_lock` | `true` | Assert root has locked/empty password |

### Sudo policy

| Variable | Default | Description |
|----------|---------|-------------|
| `user_sudo_group` | `wheel` (Arch) / `sudo` (others) | Group with sudo access |
| `user_sudo_timestamp_timeout` | `5` (default), `15` (developer), `0` (security) | Minutes sudo caches credentials |
| `user_sudo_use_pty` | `true` | CIS 5.3.5 |
| `user_sudo_logfile` | `/var/log/sudo.log` | CIS 5.3.7 |

## Profile Behavior

| Profile | `user_sudo_timestamp_timeout` |
|---------|-------------------------------|
| (none) | 5 minutes |
| `developer` | 15 minutes |
| `security` | 0 minutes (always re-enter) |

## Vault Integration

Store the password hash in vault:
```yaml
# inventory/group_vars/all/vault.yml (ansible-vault encrypted)
vault_owner_password_hash: "$6$rounds=656000$..."
```

Reference in inventory:
```yaml
# inventory/host_vars/mymachine.yml
user_owner:
  name: textyre
  password_hash: "{{ vault_owner_password_hash }}"
```

Generate hash: `python3 -c "import crypt; print(crypt.crypt('mypassword', crypt.mksalt(crypt.METHOD_SHA512)))"`

## SSH Key Setup

```yaml
user_owner:
  name: textyre
  ssh_keys:
    - "ssh-ed25519 AAAAC3... textyre@laptop"
    - "ssh-ed25519 AAAAC3... textyre@phone"
```

## Additional Users Example

```yaml
user_additional_users:
  - name: alice
    shell: /bin/bash
    groups: [video, audio]
    sudo: false
    password_hash: "{{ vault_alice_password }}"
    umask: "077"
    password_max_age: 90
  - name: bob
    shell: /bin/bash
    groups: [video, audio, wheel]
    sudo: true     # bob gets sudo
    password_hash: "{{ vault_bob_password }}"
```

## CIS Controls

| CIS ID | Control | Default |
|--------|---------|---------|
| 5.3.4 | sudo timestamp_timeout ≤ 5 min | 5 (dev: 15, security: 0) |
| 5.3.5 | sudo use_pty | `true` |
| 5.3.7 | sudo logfile | `/var/log/sudo.log` |
| 5.4.2 | umask 027 for users | 027 (owner), 077 (additional) |
| 5.4.3 | root account locked | assert only (no change) |
| 5.5.1 | password_expire_max | 365 days |
| 5.5.2 | password_expire_min | 1 day |

## Dependencies

None. The role is self-contained.

## Tags

| Tag | What it runs |
|-----|-------------|
| `user` | Everything |
| `sudo` | sudo install + policy deployment |
| `ssh` | authorized_keys management |
| `security` | CIS security checks |
| `report` | Reporting tasks only |
| `cis_5.3.4` | sudo timeout task |
| `cis_5.4.2` | umask tasks |
| `cis_5.4.3` | root lock verification |
| `cis_5.5.1` | password_expire_max |
| `cis_5.5.2` | password_expire_min |
```

**Step 2: Commit**

```bash
git add wiki/roles/user.md
git commit -m "docs(user): add wiki/roles/user.md — variables, profiles, vault, CIS controls"
```

---

### Task 14: Final lint + molecule test run

**Step 1: Sync files to VM**

```bash
bash scripts/ssh-scp-to.sh -r ansible/roles/user /home/textyre/bootstrap/ansible/roles/
```

**Step 2: Run ansible-lint**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint ansible/roles/user/"
```

Expected: no errors or warnings.

**Step 3: Run full molecule test**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/user && source ../../.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule test -s default"
```

Expected: syntax → converge → verify all PASSED.

**Step 4: Final commit (if any lint fixes were needed)**

```bash
git add ansible/roles/user/
git commit -m "fix(user): address ansible-lint findings"
```

---

## Compliance Checklist

After all tasks, verify against `wiki/standards/role-requirements.md`:

- [ ] ROLE-001: `include_vars` dispatch + `vars/` per-distro ✓
- [ ] ROLE-002: N/A (no services to manage)
- [ ] ROLE-003: `_user_supported_os` + preflight assert ✓
- [ ] ROLE-004: CIS task tags on all security tasks ✓
- [ ] ROLE-005: `tasks/verify.yml` with 3+ checks ✓
- [ ] ROLE-006: molecule verify.yml tests SSH keys, umask, groups, sudoers ✓
- [ ] ROLE-007: N/A (user is not a system/hardware role)
- [ ] ROLE-008: `report_phase` + `report_render` ✓
- [ ] ROLE-009: Profile-aware `user_sudo_timestamp_timeout` ✓
- [ ] ROLE-010: Per-feature toggles (`user_manage_*`) ✓
- [ ] ROLE-011: Only `ansible.builtin.*` + `ansible.posix.*`, no shell hacks ✓
- [ ] `wiki/roles/user.md` ✓
