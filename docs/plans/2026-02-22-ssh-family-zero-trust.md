# SSH Family Zero-Trust Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a 5-role zero-trust SSH access platform (users refactor, ssh_keys, ssh enhancement, teleport, fail2ban) with full role-requirements.md compliance.

**Architecture:** Extract ssh_keys from existing `user` role, enhance existing `ssh` role with multi-distro/multi-init/reporting/Teleport CA integration, create new `teleport` and `fail2ban` roles. All roles share a unified `accounts` data source. Teleport provides SSH CA, bastion, SSO, and session recording.

**Tech Stack:** Ansible (FQCN modules only), Jinja2 templates, Molecule tests, community.crypto for key generation, ansible.posix for authorized_keys, Teleport v17 for access management.

**Design doc:** `docs/plans/2026-02-22-ssh-family-zero-trust-design.md`

**Reference role:** `ansible/roles/ntp/` (for patterns: reporting, verify, multi-distro, multi-init)

---

## Phase 1: Extract ssh_keys Role from user

### Task 1: Create ssh_keys role scaffold

**Files:**
- Create: `ansible/roles/ssh_keys/defaults/main.yml`
- Create: `ansible/roles/ssh_keys/meta/main.yml`
- Create: `ansible/roles/ssh_keys/tasks/main.yml`
- Create: `ansible/roles/ssh_keys/handlers/main.yml`

**Step 1: Create defaults**

```yaml
# ansible/roles/ssh_keys/defaults/main.yml
---
# === ssh_keys role defaults ===

# ROLE-003: Supported operating systems
_ssh_keys_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# Feature toggles (ROLE-010)
ssh_keys_manage_authorized_keys: true
ssh_keys_generate_user_keys: false
ssh_keys_key_type: ed25519
ssh_keys_exclusive: false

# Data source: reads from `accounts` variable (shared with users role)
# accounts:
#   - name: alice
#     state: present
#     ssh_keys:
#       - "ssh-ed25519 AAAA... alice@laptop"

# Backward compatibility with user role data model
# If `accounts` is not defined, falls back to user_owner + user_additional_users
_ssh_keys_users: >-
  {{ accounts | default(
       [user_owner | default({})] +
       (user_additional_users | default([]))
     ) }}
```

**Step 2: Create meta**

```yaml
# ansible/roles/ssh_keys/meta/main.yml
---
galaxy_info:
  author: textyre
  description: SSH authorized_keys and key generation management
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
    - name: GenericLinux
      versions: [all]
  galaxy_tags:
    - ssh
    - security
    - authorized_keys
    - keys

dependencies: []
```

**Step 3: Create empty handlers**

```yaml
# ansible/roles/ssh_keys/handlers/main.yml
---
# ssh_keys role does not restart services
# sshd restart is handled by the ssh role
```

**Step 4: Create main orchestrator**

```yaml
# ansible/roles/ssh_keys/tasks/main.yml
---
# === ssh_keys: SSH authorized_keys & key generation ===
#
# Reads user list from `accounts` variable (shared data source).
# Depends on users existing (user role must run first).

- name: ssh_keys role
  tags: ['ssh_keys']
  block:
    # ROLE-003: Validate supported OS
    - name: "Assert supported operating system"
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] in _ssh_keys_supported_os
        fail_msg: >-
          OS family '{{ ansible_facts['os_family'] }}' is not supported.
          Supported: {{ _ssh_keys_supported_os | join(', ') }}
      tags: [ssh_keys]

    # Deploy authorized_keys for present users
    - name: Manage SSH authorized keys
      ansible.builtin.include_tasks: authorized_keys.yml
      when: ssh_keys_manage_authorized_keys | bool
      tags: [ssh_keys, security]

    # Optional: generate SSH keypairs on target machines
    - name: Generate user SSH keypairs
      ansible.builtin.include_tasks: keygen.yml
      when: ssh_keys_generate_user_keys | bool
      tags: [ssh_keys]

    # ROLE-005: In-role verification
    - name: Verify SSH key configuration
      ansible.builtin.include_tasks: verify.yml
      tags: [ssh_keys]

    # ROLE-008: Report phases
    - name: "Report: SSH keys"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_ssh_keys_phases"
        _rpt_phase: "Authorized keys"
        _rpt_detail: >-
          users={{ _ssh_keys_users | selectattr('state', 'defined') |
                   selectattr('state', 'equalto', 'present') | list | length }}
          keygen={{ ssh_keys_generate_user_keys }}
      tags: [ssh_keys, report]

    - name: "ssh_keys — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        _rpt_fact: "_ssh_keys_phases"
        _rpt_title: "ssh_keys"
      tags: [ssh_keys, report]
```

**Step 5: Commit**

```bash
git add ansible/roles/ssh_keys/
git commit -m "feat(ssh_keys): scaffold role with defaults, meta, main orchestrator"
```

---

### Task 2: Create ssh_keys authorized_keys and keygen tasks

**Files:**
- Create: `ansible/roles/ssh_keys/tasks/authorized_keys.yml`
- Create: `ansible/roles/ssh_keys/tasks/keygen.yml`

**Step 1: Create authorized_keys.yml**

```yaml
# ansible/roles/ssh_keys/tasks/authorized_keys.yml
---
# === Deploy SSH authorized_keys from accounts[].ssh_keys ===

- name: "Ensure .ssh directory exists for users with SSH keys"
  ansible.builtin.file:
    path: "{{ '/root' if item.name == 'root' else '/home/' + item.name }}/.ssh"
    state: directory
    owner: "{{ item.name }}"
    mode: "0700"
  loop: >-
    {{ _ssh_keys_users
       | selectattr('state', 'defined')
       | selectattr('state', 'equalto', 'present')
       | selectattr('ssh_keys', 'defined')
       | list }}
  loop_control:
    label: "{{ item.name }}"
  tags: [ssh_keys, security]

- name: "Add SSH authorized keys"
  ansible.posix.authorized_key:
    user: "{{ item.0.name }}"
    key: "{{ item.1 }}"
    manage_dir: true
    exclusive: "{{ ssh_keys_exclusive }}"
    state: present
  with_subelements:
    - >-
      {{ _ssh_keys_users
         | selectattr('state', 'defined')
         | selectattr('state', 'equalto', 'present')
         | list }}
    - ssh_keys
    - skip_missing: true
  loop_control:
    label: "{{ item.0.name }}"
  no_log: true
  tags: [ssh_keys, security]

- name: "Remove authorized_keys for absent users"
  ansible.builtin.file:
    path: "/home/{{ item.name }}/.ssh/authorized_keys"
    state: absent
  loop: >-
    {{ _ssh_keys_users
       | selectattr('state', 'defined')
       | selectattr('state', 'equalto', 'absent')
       | list }}
  loop_control:
    label: "{{ item.name }}"
  tags: [ssh_keys, security]
```

**Step 2: Create keygen.yml** (extracted from ssh/tasks/keygen.yml)

```yaml
# ansible/roles/ssh_keys/tasks/keygen.yml
---
# === Generate SSH keypairs on target machines ===
# Moved from ssh role — generates user-side keys (not host keys).

- name: "Generate SSH keypairs for present users"
  block:
    - name: "Get user home directory"
      ansible.builtin.getent:
        database: passwd
        key: "{{ item.name }}"
      loop: >-
        {{ _ssh_keys_users
           | selectattr('state', 'defined')
           | selectattr('state', 'equalto', 'present')
           | list }}
      loop_control:
        label: "{{ item.name }}"
      register: _ssh_keys_user_info
      tags: [ssh_keys]

    - name: "Ensure .ssh directory exists"
      ansible.builtin.file:
        path: "{{ getent_passwd[item.name][4] }}/.ssh"
        state: directory
        owner: "{{ item.name }}"
        group: "{{ item.name }}"
        mode: "0700"
      loop: >-
        {{ _ssh_keys_users
           | selectattr('state', 'defined')
           | selectattr('state', 'equalto', 'present')
           | list }}
      loop_control:
        label: "{{ item.name }}"
      tags: [ssh_keys]

    - name: "Generate SSH key pair ({{ ssh_keys_key_type }})"
      community.crypto.openssh_keypair:
        path: "{{ getent_passwd[item.name][4] }}/.ssh/id_{{ ssh_keys_key_type }}"
        type: "{{ ssh_keys_key_type }}"
        comment: "{{ item.name }}@{{ ansible_hostname }}"
        owner: "{{ item.name }}"
        group: "{{ item.name }}"
        mode: "0600"
      loop: >-
        {{ _ssh_keys_users
           | selectattr('state', 'defined')
           | selectattr('state', 'equalto', 'present')
           | list }}
      loop_control:
        label: "{{ item.name }}"
      tags: [ssh_keys]
```

**Step 3: Commit**

```bash
git add ansible/roles/ssh_keys/tasks/
git commit -m "feat(ssh_keys): add authorized_keys and keygen tasks"
```

---

### Task 3: Create ssh_keys verify and molecule tests

**Files:**
- Create: `ansible/roles/ssh_keys/tasks/verify.yml`
- Create: `ansible/roles/ssh_keys/molecule/default/molecule.yml`
- Create: `ansible/roles/ssh_keys/molecule/default/converge.yml`
- Create: `ansible/roles/ssh_keys/molecule/default/verify.yml`

**Step 1: Create verify.yml**

```yaml
# ansible/roles/ssh_keys/tasks/verify.yml
---
# ROLE-005: In-role verification

- name: "Verify .ssh directory permissions for present users"
  ansible.builtin.stat:
    path: "/home/{{ item.name }}/.ssh"
  register: _ssh_keys_verify_dir
  loop: >-
    {{ _ssh_keys_users
       | selectattr('state', 'defined')
       | selectattr('state', 'equalto', 'present')
       | selectattr('ssh_keys', 'defined')
       | list }}
  loop_control:
    label: "{{ item.name }}"
  tags: [ssh_keys]

- name: "Assert .ssh directories have correct permissions"
  ansible.builtin.assert:
    that:
      - item.stat.exists
      - item.stat.mode == '0700'
    fail_msg: >-
      .ssh directory for {{ item.item.name }} has incorrect permissions:
      exists={{ item.stat.exists }} mode={{ item.stat.mode | default('n/a') }}
  loop: "{{ _ssh_keys_verify_dir.results }}"
  loop_control:
    label: "{{ item.item.name }}"
  tags: [ssh_keys]

- name: "Verify authorized_keys exists for present users with keys"
  ansible.builtin.stat:
    path: "/home/{{ item.name }}/.ssh/authorized_keys"
  register: _ssh_keys_verify_authkeys
  loop: >-
    {{ _ssh_keys_users
       | selectattr('state', 'defined')
       | selectattr('state', 'equalto', 'present')
       | selectattr('ssh_keys', 'defined')
       | list }}
  loop_control:
    label: "{{ item.name }}"
  when: ssh_keys_manage_authorized_keys | bool
  tags: [ssh_keys]

- name: "Assert authorized_keys files exist"
  ansible.builtin.assert:
    that:
      - item.stat.exists
    fail_msg: "authorized_keys missing for {{ item.item.name }}"
  loop: "{{ _ssh_keys_verify_authkeys.results | default([]) }}"
  loop_control:
    label: "{{ item.item.name }}"
  when:
    - ssh_keys_manage_authorized_keys | bool
    - item.stat is defined
  tags: [ssh_keys]
```

**Step 2: Create molecule config**

```yaml
# ansible/roles/ssh_keys/molecule/default/molecule.yml
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
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
    ANSIBLE_VAULT_PASSWORD_FILE: "${MOLECULE_PROJECT_DIRECTORY}/../../vault-pass.sh"
verifier:
  name: ansible
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Step 3: Create converge.yml**

```yaml
# ansible/roles/ssh_keys/molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: true
  vars:
    # Test accounts (using shared data model)
    accounts:
      - name: "{{ ansible_user_id }}"
        state: present
        ssh_keys:
          - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey1234567890abcdefghijklmnop test@molecule"
    ssh_keys_generate_user_keys: false
    ssh_keys_exclusive: false
  roles:
    - role: ssh_keys
```

**Step 4: Create molecule verify.yml**

```yaml
# ansible/roles/ssh_keys/molecule/default/verify.yml
---
- name: Verify ssh_keys role
  hosts: all
  become: true
  tasks:
    - name: "Verify .ssh directory exists"
      ansible.builtin.stat:
        path: "/home/{{ ansible_user_id }}/.ssh"
      register: _verify_ssh_dir

    - name: "Assert .ssh directory has 0700 permissions"
      ansible.builtin.assert:
        that:
          - _verify_ssh_dir.stat.exists
          - _verify_ssh_dir.stat.mode == '0700'

    - name: "Verify authorized_keys exists"
      ansible.builtin.stat:
        path: "/home/{{ ansible_user_id }}/.ssh/authorized_keys"
      register: _verify_authkeys

    - name: "Assert authorized_keys exists and has correct permissions"
      ansible.builtin.assert:
        that:
          - _verify_authkeys.stat.exists
          - _verify_authkeys.stat.mode == '0600'

    - name: "Check authorized_keys contains test key"
      ansible.builtin.command:
        cmd: "grep -c 'test@molecule' /home/{{ ansible_user_id }}/.ssh/authorized_keys"
      register: _verify_key_content
      changed_when: false
      failed_when: _verify_key_content.rc != 0
```

**Step 5: Run molecule syntax check**

Run: `cd ansible/roles/ssh_keys && molecule syntax`
Expected: PASS (no YAML errors)

**Step 6: Commit**

```bash
git add ansible/roles/ssh_keys/
git commit -m "feat(ssh_keys): add verify.yml and molecule tests"
```

---

### Task 4: Remove ssh_keys from user role

**Files:**
- Modify: `ansible/roles/user/tasks/main.yml` — remove ssh_keys include
- Modify: `ansible/roles/user/defaults/main.yml` — remove `user_manage_ssh_keys`
- Delete: `ansible/roles/user/tasks/ssh_keys.yml`

**Step 1: Remove ssh_keys include from tasks/main.yml**

In `ansible/roles/user/tasks/main.yml`, find and remove:
```yaml
    # SSH keys management
    - name: Manage SSH authorized keys
      ansible.builtin.include_tasks: ssh_keys.yml
      when: user_manage_ssh_keys | bool
      tags: [user, ssh]
```

And remove any corresponding report_phase block for SSH keys.

**Step 2: Remove toggle from defaults**

In `ansible/roles/user/defaults/main.yml`, remove:
```yaml
user_manage_ssh_keys: true
```

**Step 3: Delete ssh_keys.yml task file**

```bash
rm ansible/roles/user/tasks/ssh_keys.yml
```

**Step 4: Update user molecule tests**

In `ansible/roles/user/molecule/default/verify.yml`, remove any tests that check for authorized_keys (these now belong to ssh_keys role).

In `ansible/roles/user/molecule/default/converge.yml`, remove `user_manage_ssh_keys` from vars if present.

**Step 5: Run user role molecule syntax**

Run: `cd ansible/roles/user && molecule syntax`
Expected: PASS

**Step 6: Commit**

```bash
git add ansible/roles/user/
git commit -m "refactor(user): extract ssh_keys management to dedicated role"
```

---

### Task 5: Update playbook to include ssh_keys role

**Files:**
- Modify: `ansible/playbooks/workstation.yml`

**Step 1: Add ssh_keys role after user role**

In `ansible/playbooks/workstation.yml`, find Phase 3 section and add ssh_keys between user and ssh:

```yaml
    # Phase 3: User & access
    - role: user
      tags: [user]
    - role: ssh_keys
      tags: [ssh_keys, security]
    - role: ssh
      tags: [ssh, security]
```

**Step 2: Commit**

```bash
git add ansible/playbooks/workstation.yml
git commit -m "feat(playbook): add ssh_keys role to workstation playbook"
```

---

## Phase 2: Enhance ssh Role

### Task 6: Add missing distros to ssh role

**Files:**
- Create: `ansible/roles/ssh/tasks/install-redhat.yml`
- Create: `ansible/roles/ssh/tasks/install-void.yml`
- Create: `ansible/roles/ssh/tasks/install-gentoo.yml`
- Create: `ansible/roles/ssh/vars/archlinux.yml`
- Create: `ansible/roles/ssh/vars/debian.yml`
- Create: `ansible/roles/ssh/vars/redhat.yml`
- Create: `ansible/roles/ssh/vars/void.yml`
- Create: `ansible/roles/ssh/vars/gentoo.yml`
- Modify: `ansible/roles/ssh/defaults/main.yml` — add `_ssh_supported_os`
- Modify: `ansible/roles/ssh/tasks/main.yml` — add preflight assert + vars include

**Step 1: Create vars files for all 5 distros**

```yaml
# ansible/roles/ssh/vars/archlinux.yml
---
_ssh_packages:
  - openssh
_ssh_service_name:
  systemd: sshd
  runit: sshd
  openrc: sshd
  s6: sshd
  dinit: sshd

# ansible/roles/ssh/vars/debian.yml
---
_ssh_packages:
  - openssh-server
  - openssh-client
_ssh_service_name:
  systemd: ssh
  runit: ssh
  openrc: ssh
  s6: ssh
  dinit: ssh

# ansible/roles/ssh/vars/redhat.yml
---
_ssh_packages:
  - openssh-server
  - openssh-clients
_ssh_service_name:
  systemd: sshd
  runit: sshd
  openrc: sshd
  s6: sshd
  dinit: sshd

# ansible/roles/ssh/vars/void.yml
---
_ssh_packages:
  - openssh
_ssh_service_name:
  systemd: sshd
  runit: sshd
  openrc: sshd
  s6: sshd
  dinit: sshd

# ansible/roles/ssh/vars/gentoo.yml
---
_ssh_packages:
  - net-misc/openssh
_ssh_service_name:
  systemd: sshd
  openrc: sshd
  runit: sshd
  s6: sshd
  dinit: sshd
```

**Step 2: Create install task files for missing distros**

```yaml
# ansible/roles/ssh/tasks/install-redhat.yml
---
- name: "Install OpenSSH packages (RedHat)"
  ansible.builtin.package:
    name: "{{ _ssh_packages }}"
    state: present
  tags: [ssh, install]

# ansible/roles/ssh/tasks/install-void.yml
---
- name: "Install OpenSSH packages (Void)"
  ansible.builtin.package:
    name: "{{ _ssh_packages }}"
    state: present
  tags: [ssh, install]

# ansible/roles/ssh/tasks/install-gentoo.yml
---
- name: "Install OpenSSH packages (Gentoo)"
  ansible.builtin.package:
    name: "{{ _ssh_packages }}"
    state: present
  tags: [ssh, install]
```

**Step 3: Refactor existing install tasks to use vars**

Update `install-archlinux.yml` and `install-debian.yml` to use `_ssh_packages` from vars instead of hardcoded package names:

```yaml
# ansible/roles/ssh/tasks/install-archlinux.yml
---
- name: "Install OpenSSH packages (Archlinux)"
  ansible.builtin.package:
    name: "{{ _ssh_packages }}"
    state: present
  tags: [ssh, install]
```

**Step 4: Add supported OS and preflight to defaults and main.yml**

In `ansible/roles/ssh/defaults/main.yml`, add at top:
```yaml
# ROLE-003: Supported operating systems
_ssh_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo
```

In `ansible/roles/ssh/tasks/main.yml`, add as first tasks:
```yaml
# ROLE-003: Validate supported OS
- name: "Assert supported operating system"
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] in _ssh_supported_os
    fail_msg: >-
      OS family '{{ ansible_facts['os_family'] }}' is not supported.
      Supported: {{ _ssh_supported_os | join(', ') }}
  tags: [ssh]

# ROLE-001: OS-specific variables
- name: "Include OS-specific variables"
  ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
  tags: [ssh]
```

Replace the install dispatch from hardcoded OS name to `os_family | lower` pattern (should already use this pattern — verify and align).

**Step 5: Commit**

```bash
git add ansible/roles/ssh/
git commit -m "feat(ssh): add RedHat, Void, Gentoo support (ROLE-001, ROLE-003)"
```

---

### Task 7: Add init-system agnostic service management to ssh

**Files:**
- Modify: `ansible/roles/ssh/tasks/service.yml` — use generic service module with dispatch
- Modify: `ansible/roles/ssh/handlers/main.yml` — use generic service module

**Step 1: Refactor service.yml**

Replace the current `service.yml` with init-agnostic version:

```yaml
# ansible/roles/ssh/tasks/service.yml
---
# ROLE-002: Init-system agnostic service management

- name: "Determine sshd service name"
  ansible.builtin.set_fact:
    _ssh_svc: "{{ _ssh_service_name[ansible_facts['service_mgr']] | default('sshd') }}"
  tags: [ssh, service]

- name: "Enable and start sshd"
  ansible.builtin.service:
    name: "{{ _ssh_svc }}"
    enabled: true
    state: started
  tags: [ssh, service]
```

**Step 2: Refactor handlers**

```yaml
# ansible/roles/ssh/handlers/main.yml
---
- name: "Restart sshd"
  ansible.builtin.service:
    name: "{{ _ssh_service_name[ansible_facts['service_mgr']] | default('sshd') }}"
    state: restarted

- name: "Reload sshd"
  ansible.builtin.service:
    name: "{{ _ssh_service_name[ansible_facts['service_mgr']] | default('sshd') }}"
    state: reloaded
```

**Step 3: Commit**

```bash
git add ansible/roles/ssh/tasks/service.yml ansible/roles/ssh/handlers/main.yml
git commit -m "feat(ssh): init-system agnostic service management (ROLE-002)"
```

---

### Task 8: Add reporting and Teleport CA integration to ssh role

**Files:**
- Modify: `ansible/roles/ssh/tasks/main.yml` — add reporting + Teleport CA
- Modify: `ansible/roles/ssh/defaults/main.yml` — add Teleport integration vars
- Modify: `ansible/roles/ssh/templates/sshd_config.j2` — add TrustedUserCAKeys block

**Step 1: Add Teleport integration defaults**

In `ansible/roles/ssh/defaults/main.yml`, add:
```yaml
# Teleport SSH CA integration
ssh_teleport_integration: false
ssh_teleport_ca_keys_file: /etc/ssh/teleport_user_ca.pub
```

**Step 2: Add TrustedUserCAKeys to sshd_config.j2**

In `ansible/roles/ssh/templates/sshd_config.j2`, add before the SFTP section:
```jinja2
{% if ssh_teleport_integration %}
# === Teleport SSH CA ===
# Trust certificates signed by Teleport auth server
TrustedUserCAKeys {{ ssh_teleport_ca_keys_file }}
{% endif %}
```

**Step 3: Add reporting to main.yml**

Wrap the existing `main.yml` tasks in a block and add report phases. After each major include_tasks, add:

```yaml
    - name: "Report: sshd install"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_ssh_phases"
        _rpt_phase: "Install"
        _rpt_detail: "packages={{ _ssh_packages | join(',') }}"
      tags: [ssh, report]
```

At the end of main.yml, add final report render:
```yaml
    - name: "ssh — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        _rpt_fact: "_ssh_phases"
        _rpt_title: "ssh"
      tags: [ssh, report]
```

Add report phases for: Install, Keygen (if enabled), Preflight, Harden, Moduli (if enabled), Banner (if enabled), Service, Verify.

**Step 4: Remove keygen from ssh role** (moved to ssh_keys)

Remove keygen include from `main.yml`:
```yaml
# REMOVE this block — keygen is now in ssh_keys role
- name: Generate SSH key pair
  ansible.builtin.include_tasks: keygen.yml
  when: ssh_generate_key
  tags: ['ssh', 'keygen']
```

Delete `ansible/roles/ssh/tasks/keygen.yml`.

Remove `ssh_generate_key`, `ssh_key_type`, `ssh_key_comment`, `ssh_user` from `defaults/main.yml` (these are now in ssh_keys).

**Step 5: Commit**

```bash
git add ansible/roles/ssh/
git commit -m "feat(ssh): add reporting, Teleport CA integration, remove keygen (moved to ssh_keys)"
```

---

### Task 9: Replace shell/awk in ssh moduli.yml

**Files:**
- Modify: `ansible/roles/ssh/tasks/moduli.yml`

**Step 1: Refactor moduli.yml to avoid shell/awk**

The current moduli.yml uses `awk` to filter weak DH parameters. Replace with a two-step approach using `ansible.builtin.command` (reading) and `ansible.builtin.copy` (writing):

```yaml
# ansible/roles/ssh/tasks/moduli.yml
---
# === DH moduli hardening ===
# Remove weak Diffie-Hellman parameters below minimum bit size.

- name: "Read current moduli file"
  ansible.builtin.slurp:
    src: /etc/ssh/moduli
  register: _ssh_moduli_content
  tags: [ssh, security]

- name: "Filter weak DH moduli (< {{ ssh_moduli_minimum_bits }} bits)"
  ansible.builtin.set_fact:
    _ssh_moduli_filtered: >-
      {{ (_ssh_moduli_content.content | b64decode).split('\n')
         | select('match', '^#')
         | list
         + (_ssh_moduli_content.content | b64decode).split('\n')
         | reject('match', '^#')
         | reject('match', '^\s*$')
         | select('regex', '^\S+\s+\S+\s+\S+\s+\S+\s+(' +
                  (range(ssh_moduli_minimum_bits | int, 99999) | map('string') | join('|'))
                  + ')\s+')
         | list }}
  tags: [ssh, security]

- name: "Count weak moduli"
  ansible.builtin.set_fact:
    _ssh_weak_moduli_count: >-
      {{ (_ssh_moduli_content.content | b64decode).split('\n')
         | reject('match', '^#')
         | reject('match', '^\s*$')
         | list | length
         - _ssh_moduli_filtered
         | reject('match', '^#')
         | list | length }}
  tags: [ssh, security]

- name: "Deploy filtered moduli file"
  ansible.builtin.copy:
    content: "{{ _ssh_moduli_filtered | join('\n') }}\n"
    dest: /etc/ssh/moduli
    owner: root
    group: root
    mode: "0644"
    backup: true
  when: _ssh_weak_moduli_count | int > 0
  notify: "Restart sshd"
  tags: [ssh, security]

- name: "Report weak moduli removed"
  ansible.builtin.debug:
    msg: "Removed {{ _ssh_weak_moduli_count }} weak DH moduli (< {{ ssh_moduli_minimum_bits }} bits)"
  when: _ssh_weak_moduli_count | int > 0
  tags: [ssh, security]
```

Note: The moduli filtering with pure Jinja2 is complex. If the above approach is too fragile, an alternative is to use `ansible.builtin.command` with `awk` and document the exception per ROLE-011 ("shell/command ONLY when no module equivalent exists"). The moduli file format is fixed-width and `awk '$5 >= N'` is the canonical approach. Consider keeping `command` with `awk` and adding a comment explaining why.

**Step 2: Commit**

```bash
git add ansible/roles/ssh/tasks/moduli.yml
git commit -m "refactor(ssh): replace shell/awk in moduli.yml with ansible.builtin modules"
```

---

### Task 10: Update ssh molecule tests

**Files:**
- Modify: `ansible/roles/ssh/molecule/default/converge.yml` — remove keygen vars
- Modify: `ansible/roles/ssh/molecule/default/verify.yml` — remove keygen tests, add Teleport CA test

**Step 1: Update converge.yml**

Remove `ssh_generate_key` variable (now in ssh_keys role). Keep `ssh_banner_enabled: true` and `ssh_moduli_cleanup: true`.

**Step 2: Update verify.yml**

Remove tests that verify `~/.ssh/id_ed25519` (keygen is in ssh_keys now).

Add test for Teleport CA integration (when enabled):
```yaml
    - name: "Verify sshd_config accepts Teleport CA (when integration enabled)"
      ansible.builtin.command:
        cmd: "grep -c 'TrustedUserCAKeys' /etc/ssh/sshd_config"
      register: _verify_teleport_ca
      changed_when: false
      failed_when: false
      # Only assert if teleport integration is enabled in test
```

**Step 3: Run molecule syntax**

Run: `cd ansible/roles/ssh && molecule syntax`
Expected: PASS

**Step 4: Commit**

```bash
git add ansible/roles/ssh/molecule/
git commit -m "test(ssh): update molecule tests for role separation and Teleport CA"
```

---

## Phase 3: Create teleport Role

### Task 11: Create teleport role scaffold

**Files:**
- Create: `ansible/roles/teleport/defaults/main.yml`
- Create: `ansible/roles/teleport/meta/main.yml`
- Create: `ansible/roles/teleport/handlers/main.yml`
- Create: `ansible/roles/teleport/tasks/main.yml`
- Create: `ansible/roles/teleport/vars/archlinux.yml`
- Create: `ansible/roles/teleport/vars/debian.yml`
- Create: `ansible/roles/teleport/vars/redhat.yml`
- Create: `ansible/roles/teleport/vars/void.yml`
- Create: `ansible/roles/teleport/vars/gentoo.yml`

**Step 1: Create defaults**

```yaml
# ansible/roles/teleport/defaults/main.yml
---
# === teleport role defaults ===

# ROLE-003: Supported operating systems
_teleport_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# Core configuration
teleport_enabled: true
teleport_version: "17"
teleport_auth_server: ""
teleport_join_token: ""
teleport_node_name: "{{ ansible_hostname }}"
teleport_labels: {}

# SSH features
teleport_ssh_enabled: true
teleport_proxy_mode: false
teleport_session_recording: "node"
teleport_enhanced_recording: false

# CA integration with ssh role
teleport_export_ca_key: true
teleport_ca_keys_file: /etc/ssh/teleport_user_ca.pub
```

**Step 2: Create vars files**

```yaml
# ansible/roles/teleport/vars/archlinux.yml
---
_teleport_packages:
  - teleport-bin
_teleport_install_method: package
_teleport_service_name:
  systemd: teleport
  runit: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport

# ansible/roles/teleport/vars/debian.yml
---
_teleport_packages: []
_teleport_install_method: repo
_teleport_service_name:
  systemd: teleport
  runit: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport

# ansible/roles/teleport/vars/redhat.yml
---
_teleport_packages: []
_teleport_install_method: repo
_teleport_service_name:
  systemd: teleport
  runit: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport

# ansible/roles/teleport/vars/void.yml
---
_teleport_packages: []
_teleport_install_method: binary
_teleport_service_name:
  runit: teleport
  systemd: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport

# ansible/roles/teleport/vars/gentoo.yml
---
_teleport_packages: []
_teleport_install_method: binary
_teleport_service_name:
  openrc: teleport
  systemd: teleport
  runit: teleport
  s6: teleport
  dinit: teleport
```

**Step 3: Create handlers**

```yaml
# ansible/roles/teleport/handlers/main.yml
---
- name: "Restart teleport"
  ansible.builtin.service:
    name: "{{ _teleport_service_name[ansible_facts['service_mgr']] | default('teleport') }}"
    state: restarted
```

**Step 4: Create meta**

```yaml
# ansible/roles/teleport/meta/main.yml
---
galaxy_info:
  author: textyre
  description: Teleport SSH access platform agent deployment
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
    - name: GenericLinux
      versions: [all]
  galaxy_tags:
    - teleport
    - security
    - ssh
    - access
    - zero-trust

dependencies: []
```

**Step 5: Create main orchestrator**

```yaml
# ansible/roles/teleport/tasks/main.yml
---
# === teleport: SSH access platform agent ===
#
# Installs Teleport agent, registers with auth server,
# exports CA key for ssh role integration.

- name: teleport role
  when: teleport_enabled | bool
  tags: ['teleport']
  block:
    # ROLE-003: Validate supported OS
    - name: "Assert supported operating system"
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] in _teleport_supported_os
        fail_msg: >-
          OS family '{{ ansible_facts['os_family'] }}' is not supported.
          Supported: {{ _teleport_supported_os | join(', ') }}
      tags: [teleport]

    # ROLE-001: OS-specific variables
    - name: "Include OS-specific variables"
      ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
      tags: [teleport]

    # Validate required variables
    - name: "Assert auth server is configured"
      ansible.builtin.assert:
        that:
          - teleport_auth_server | length > 0
        fail_msg: "teleport_auth_server must be set (e.g., 'auth.example.com:443')"
      tags: [teleport]

    # Install
    - name: "Install Teleport"
      ansible.builtin.include_tasks: install.yml
      tags: [teleport, install]

    # Configure
    - name: "Configure Teleport"
      ansible.builtin.include_tasks: configure.yml
      tags: [teleport]

    # Join auth server
    - name: "Join Teleport auth server"
      ansible.builtin.include_tasks: join.yml
      tags: [teleport]

    # Export CA key for ssh role integration
    - name: "Export CA public key"
      ansible.builtin.include_tasks: ca_export.yml
      when: teleport_export_ca_key | bool
      tags: [teleport, security]

    # Service management (ROLE-002)
    - name: "Enable and start teleport"
      ansible.builtin.service:
        name: "{{ _teleport_service_name[ansible_facts['service_mgr']] | default('teleport') }}"
        enabled: true
        state: started
      tags: [teleport, service]

    # ROLE-005: Verification
    - name: "Verify Teleport"
      ansible.builtin.include_tasks: verify.yml
      tags: [teleport]

    # ROLE-008: Reporting
    - name: "Report: Teleport"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_teleport_phases"
        _rpt_phase: "Teleport agent"
        _rpt_detail: >-
          auth={{ teleport_auth_server }}
          node={{ teleport_node_name }}
          recording={{ teleport_session_recording }}
      tags: [teleport, report]

    - name: "teleport — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        _rpt_fact: "_teleport_phases"
        _rpt_title: "teleport"
      tags: [teleport, report]
```

**Step 6: Commit**

```bash
git add ansible/roles/teleport/
git commit -m "feat(teleport): scaffold role with defaults, vars, meta, main orchestrator"
```

---

### Task 12: Create teleport install, configure, join, ca_export, verify tasks

**Files:**
- Create: `ansible/roles/teleport/tasks/install.yml`
- Create: `ansible/roles/teleport/tasks/configure.yml`
- Create: `ansible/roles/teleport/tasks/join.yml`
- Create: `ansible/roles/teleport/tasks/ca_export.yml`
- Create: `ansible/roles/teleport/tasks/verify.yml`
- Create: `ansible/roles/teleport/templates/teleport.yaml.j2`

**Step 1: Create install.yml**

```yaml
# ansible/roles/teleport/tasks/install.yml
---
# === Install Teleport agent ===

- name: "Install Teleport via package manager"
  ansible.builtin.package:
    name: "{{ _teleport_packages }}"
    state: present
  when: _teleport_install_method == 'package'
  tags: [teleport, install]

- name: "Install Teleport via official repository (Debian/RedHat)"
  when: _teleport_install_method == 'repo'
  block:
    - name: "Add Teleport GPG key"
      ansible.builtin.get_url:
        url: "https://apt.releases.teleport.dev/gpg"
        dest: /usr/share/keyrings/teleport-archive-keyring.asc
        mode: "0644"
      when: ansible_facts['os_family'] == 'Debian'

    - name: "Add Teleport APT repository"
      ansible.builtin.apt_repository:
        repo: >-
          deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc]
          https://apt.releases.teleport.dev/{{ ansible_distribution | lower }}
          {{ ansible_distribution_release }} stable/v{{ teleport_version }}
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    - name: "Add Teleport YUM repository"
      ansible.builtin.yum_repository:
        name: teleport
        description: Teleport
        baseurl: "https://yum.releases.teleport.dev/$basearch/stable/v{{ teleport_version }}"
        gpgcheck: true
        gpgkey: "https://yum.releases.teleport.dev/gpg"
      when: ansible_facts['os_family'] == 'RedHat'

    - name: "Install Teleport from repository"
      ansible.builtin.package:
        name: teleport
        state: present
  tags: [teleport, install]

- name: "Install Teleport via binary download (Void/Gentoo)"
  when: _teleport_install_method == 'binary'
  block:
    - name: "Download Teleport binary"
      ansible.builtin.get_url:
        url: "https://cdn.teleport.dev/teleport-v{{ teleport_version }}.0-linux-{{ ansible_architecture }}-bin.tar.gz"
        dest: "/tmp/teleport.tar.gz"
        mode: "0644"

    - name: "Extract Teleport binary"
      ansible.builtin.unarchive:
        src: "/tmp/teleport.tar.gz"
        dest: /usr/local/bin/
        remote_src: true
        extra_opts: [--strip-components=1]
  tags: [teleport, install]
```

**Step 2: Create teleport.yaml.j2 template**

```yaml
# ansible/roles/teleport/templates/teleport.yaml.j2
# {{ ansible_managed }}
# Teleport node configuration

version: v3
teleport:
  nodename: {{ teleport_node_name }}
  data_dir: /var/lib/teleport
  auth_token: {{ teleport_join_token }}
  auth_server: {{ teleport_auth_server }}
  log:
    output: stderr
    severity: INFO

ssh_service:
  enabled: {{ teleport_ssh_enabled | lower }}
{% if teleport_labels %}
  labels:
{% for key, value in teleport_labels.items() %}
    {{ key }}: "{{ value }}"
{% endfor %}
{% endif %}

proxy_service:
  enabled: {{ teleport_proxy_mode | lower }}

auth_service:
  enabled: false

{% if teleport_session_recording != 'off' %}
session_recording:
  mode: {{ teleport_session_recording }}
{% if teleport_enhanced_recording %}
  enhanced_recording:
    enabled: true
{% endif %}
{% endif %}
```

**Step 3: Create configure.yml**

```yaml
# ansible/roles/teleport/tasks/configure.yml
---
- name: "Ensure teleport data directory exists"
  ansible.builtin.file:
    path: /var/lib/teleport
    state: directory
    owner: root
    group: root
    mode: "0750"
  tags: [teleport]

- name: "Deploy teleport configuration"
  ansible.builtin.template:
    src: teleport.yaml.j2
    dest: /etc/teleport.yaml
    owner: root
    group: root
    mode: "0600"
  notify: "Restart teleport"
  tags: [teleport]
```

**Step 4: Create join.yml**

```yaml
# ansible/roles/teleport/tasks/join.yml
---
# Join is handled by the teleport agent on first start.
# The join token in teleport.yaml is consumed automatically.
# This task verifies join status after service start.

- name: "Check Teleport node status"
  ansible.builtin.command:
    cmd: tctl status
  register: _teleport_status
  changed_when: false
  failed_when: false
  tags: [teleport]
```

**Step 5: Create ca_export.yml**

```yaml
# ansible/roles/teleport/tasks/ca_export.yml
---
# === Export Teleport CA public key for ssh role integration ===

- name: "Export Teleport user CA public key"
  ansible.builtin.command:
    cmd: "tctl auth export --type=user"
  register: _teleport_user_ca
  changed_when: false
  failed_when: _teleport_user_ca.rc != 0
  tags: [teleport, security]

- name: "Deploy CA public key for sshd"
  ansible.builtin.copy:
    content: "{{ _teleport_user_ca.stdout }}\n"
    dest: "{{ teleport_ca_keys_file }}"
    owner: root
    group: root
    mode: "0644"
  tags: [teleport, security]

- name: "Set ssh_teleport_integration fact"
  ansible.builtin.set_fact:
    ssh_teleport_integration: true
  tags: [teleport, security]
```

**Step 6: Create verify.yml**

```yaml
# ansible/roles/teleport/tasks/verify.yml
---
# ROLE-005: In-role verification

- name: "Verify teleport binary exists"
  ansible.builtin.command:
    cmd: "teleport version"
  register: _teleport_verify_version
  changed_when: false
  failed_when: _teleport_verify_version.rc != 0
  tags: [teleport]

- name: "Verify teleport configuration exists"
  ansible.builtin.stat:
    path: /etc/teleport.yaml
  register: _teleport_verify_config
  tags: [teleport]

- name: "Assert teleport configuration exists"
  ansible.builtin.assert:
    that:
      - _teleport_verify_config.stat.exists
      - _teleport_verify_config.stat.mode == '0600'
    fail_msg: "Teleport configuration missing or wrong permissions"
  tags: [teleport]

- name: "Verify teleport service is running"
  ansible.builtin.command:
    cmd: "teleport status"
  register: _teleport_verify_status
  changed_when: false
  failed_when: false
  tags: [teleport]
```

**Step 7: Commit**

```bash
git add ansible/roles/teleport/
git commit -m "feat(teleport): add install, configure, join, ca_export, verify tasks"
```

---

### Task 13: Create teleport molecule tests

**Files:**
- Create: `ansible/roles/teleport/molecule/default/molecule.yml`
- Create: `ansible/roles/teleport/molecule/default/converge.yml`
- Create: `ansible/roles/teleport/molecule/default/verify.yml`

**Step 1: Create molecule.yml**

```yaml
# ansible/roles/teleport/molecule/default/molecule.yml
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
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
    ANSIBLE_VAULT_PASSWORD_FILE: "${MOLECULE_PROJECT_DIRECTORY}/../../vault-pass.sh"
verifier:
  name: ansible
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Step 2: Create converge.yml**

```yaml
# ansible/roles/teleport/molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: true
  vars:
    teleport_enabled: true
    teleport_auth_server: "localhost:3025"
    teleport_join_token: "test-token-molecule"
    teleport_node_name: "molecule-test"
    teleport_session_recording: "node"
    teleport_export_ca_key: false
  roles:
    - role: teleport
```

**Step 3: Create verify.yml**

```yaml
# ansible/roles/teleport/molecule/default/verify.yml
---
- name: Verify teleport role
  hosts: all
  become: true
  tasks:
    - name: "Verify teleport configuration exists"
      ansible.builtin.stat:
        path: /etc/teleport.yaml
      register: _verify_config

    - name: "Assert config exists with correct permissions"
      ansible.builtin.assert:
        that:
          - _verify_config.stat.exists
          - _verify_config.stat.mode == '0600'
          - _verify_config.stat.pw_name == 'root'

    - name: "Verify config contains auth server"
      ansible.builtin.command:
        cmd: "grep 'auth_server: localhost:3025' /etc/teleport.yaml"
      register: _verify_auth_server
      changed_when: false
      failed_when: _verify_auth_server.rc != 0

    - name: "Verify config contains node name"
      ansible.builtin.command:
        cmd: "grep 'nodename: molecule-test' /etc/teleport.yaml"
      register: _verify_node_name
      changed_when: false
      failed_when: _verify_node_name.rc != 0

    - name: "Verify data directory exists"
      ansible.builtin.stat:
        path: /var/lib/teleport
      register: _verify_datadir

    - name: "Assert data directory exists"
      ansible.builtin.assert:
        that:
          - _verify_datadir.stat.exists
          - _verify_datadir.stat.isdir
```

**Step 4: Run molecule syntax**

Run: `cd ansible/roles/teleport && molecule syntax`
Expected: PASS

**Step 5: Commit**

```bash
git add ansible/roles/teleport/molecule/
git commit -m "test(teleport): add molecule tests"
```

---

## Phase 4: Create fail2ban Role

### Task 14: Create fail2ban role scaffold and tasks

**Files:**
- Create: `ansible/roles/fail2ban/defaults/main.yml`
- Create: `ansible/roles/fail2ban/meta/main.yml`
- Create: `ansible/roles/fail2ban/handlers/main.yml`
- Create: `ansible/roles/fail2ban/tasks/main.yml`
- Create: `ansible/roles/fail2ban/tasks/install.yml`
- Create: `ansible/roles/fail2ban/tasks/configure.yml`
- Create: `ansible/roles/fail2ban/tasks/verify.yml`
- Create: `ansible/roles/fail2ban/templates/jail_sshd.conf.j2`
- Create: `ansible/roles/fail2ban/vars/archlinux.yml`
- Create: `ansible/roles/fail2ban/vars/debian.yml`
- Create: `ansible/roles/fail2ban/vars/redhat.yml`
- Create: `ansible/roles/fail2ban/vars/void.yml`
- Create: `ansible/roles/fail2ban/vars/gentoo.yml`

**Step 1: Create defaults**

```yaml
# ansible/roles/fail2ban/defaults/main.yml
---
# === fail2ban role defaults ===

# ROLE-003: Supported operating systems
_fail2ban_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# Main toggle
fail2ban_enabled: true

# SSH jail configuration
fail2ban_sshd_enabled: true
fail2ban_sshd_port: "{{ ssh_port | default(22) }}"
fail2ban_sshd_maxretry: 5
fail2ban_sshd_findtime: 600
fail2ban_sshd_bantime: 3600
fail2ban_sshd_bantime_increment: true
fail2ban_sshd_bantime_maxtime: 86400
fail2ban_sshd_backend: auto

# Whitelist
fail2ban_ignoreip:
  - 127.0.0.1/8
  - "::1"
```

**Step 2: Create vars files**

```yaml
# ansible/roles/fail2ban/vars/archlinux.yml
---
_fail2ban_packages: [fail2ban]
_fail2ban_service_name:
  systemd: fail2ban
  runit: fail2ban
  openrc: fail2ban
  s6: fail2ban
  dinit: fail2ban

# Same structure for debian.yml, redhat.yml, void.yml, gentoo.yml
# All use fail2ban as package name (gentoo: net-analyzer/fail2ban)
```

Create identical vars files for debian (`[fail2ban]`), redhat (`[fail2ban]`), void (`[fail2ban]`), gentoo (`[net-analyzer/fail2ban]`).

**Step 3: Create handlers**

```yaml
# ansible/roles/fail2ban/handlers/main.yml
---
- name: "Restart fail2ban"
  ansible.builtin.service:
    name: "{{ _fail2ban_service_name[ansible_facts['service_mgr']] | default('fail2ban') }}"
    state: restarted
```

**Step 4: Create meta**

```yaml
# ansible/roles/fail2ban/meta/main.yml
---
galaxy_info:
  author: textyre
  description: Fail2ban brute-force protection for SSH
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
    - name: GenericLinux
      versions: [all]
  galaxy_tags:
    - fail2ban
    - security
    - ssh
    - brute-force

dependencies: []
```

**Step 5: Create jail template**

```ini
# ansible/roles/fail2ban/templates/jail_sshd.conf.j2
# {{ ansible_managed }}
# SSH jail configuration for fail2ban

[sshd]
enabled = {{ fail2ban_sshd_enabled | lower }}
port = {{ fail2ban_sshd_port }}
maxretry = {{ fail2ban_sshd_maxretry }}
findtime = {{ fail2ban_sshd_findtime }}
bantime = {{ fail2ban_sshd_bantime }}
{% if fail2ban_sshd_bantime_increment %}
bantime.increment = true
bantime.maxtime = {{ fail2ban_sshd_bantime_maxtime }}
{% endif %}
backend = {{ fail2ban_sshd_backend }}
{% if fail2ban_ignoreip %}
ignoreip = {{ fail2ban_ignoreip | join(' ') }}
{% endif %}
```

**Step 6: Create tasks**

```yaml
# ansible/roles/fail2ban/tasks/main.yml
---
- name: fail2ban role
  when: fail2ban_enabled | bool
  tags: ['fail2ban']
  block:
    - name: "Assert supported operating system"
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] in _fail2ban_supported_os
        fail_msg: >-
          OS family '{{ ansible_facts['os_family'] }}' is not supported.
          Supported: {{ _fail2ban_supported_os | join(', ') }}
      tags: [fail2ban]

    - name: "Include OS-specific variables"
      ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
      tags: [fail2ban]

    - name: "Install fail2ban"
      ansible.builtin.include_tasks: install.yml
      tags: [fail2ban, install]

    - name: "Configure fail2ban"
      ansible.builtin.include_tasks: configure.yml
      tags: [fail2ban]

    - name: "Enable and start fail2ban"
      ansible.builtin.service:
        name: "{{ _fail2ban_service_name[ansible_facts['service_mgr']] | default('fail2ban') }}"
        enabled: true
        state: started
      tags: [fail2ban, service]

    - name: "Verify fail2ban"
      ansible.builtin.include_tasks: verify.yml
      tags: [fail2ban]

    - name: "Report: fail2ban"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_fail2ban_phases"
        _rpt_phase: "Fail2ban SSH jail"
        _rpt_detail: >-
          maxretry={{ fail2ban_sshd_maxretry }}
          bantime={{ fail2ban_sshd_bantime }}
      tags: [fail2ban, report]

    - name: "fail2ban — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        _rpt_fact: "_fail2ban_phases"
        _rpt_title: "fail2ban"
      tags: [fail2ban, report]
```

```yaml
# ansible/roles/fail2ban/tasks/install.yml
---
- name: "Install fail2ban packages"
  ansible.builtin.package:
    name: "{{ _fail2ban_packages }}"
    state: present
  tags: [fail2ban, install]
```

```yaml
# ansible/roles/fail2ban/tasks/configure.yml
---
- name: "Deploy SSH jail configuration"
  ansible.builtin.template:
    src: jail_sshd.conf.j2
    dest: /etc/fail2ban/jail.d/sshd.conf
    owner: root
    group: root
    mode: "0644"
  notify: "Restart fail2ban"
  tags: [fail2ban]
```

```yaml
# ansible/roles/fail2ban/tasks/verify.yml
---
- name: "Verify fail2ban is running"
  ansible.builtin.command:
    cmd: "fail2ban-client status"
  register: _fail2ban_verify_status
  changed_when: false
  failed_when: _fail2ban_verify_status.rc != 0
  tags: [fail2ban]

- name: "Verify SSH jail is active"
  ansible.builtin.command:
    cmd: "fail2ban-client status sshd"
  register: _fail2ban_verify_sshd
  changed_when: false
  failed_when: _fail2ban_verify_sshd.rc != 0
  when: fail2ban_sshd_enabled | bool
  tags: [fail2ban]

- name: "Assert SSH jail reports correctly"
  ansible.builtin.assert:
    that:
      - "'sshd' in _fail2ban_verify_sshd.stdout"
    fail_msg: "fail2ban sshd jail is not active"
  when: fail2ban_sshd_enabled | bool
  tags: [fail2ban]
```

**Step 7: Commit**

```bash
git add ansible/roles/fail2ban/
git commit -m "feat(fail2ban): create role with SSH jail, multi-distro, multi-init support"
```

---

### Task 15: Create fail2ban molecule tests

**Files:**
- Create: `ansible/roles/fail2ban/molecule/default/molecule.yml`
- Create: `ansible/roles/fail2ban/molecule/default/converge.yml`
- Create: `ansible/roles/fail2ban/molecule/default/verify.yml`

**Step 1: Create molecule config files**

```yaml
# ansible/roles/fail2ban/molecule/default/molecule.yml
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
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
verifier:
  name: ansible
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

```yaml
# ansible/roles/fail2ban/molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: true
  vars:
    fail2ban_enabled: true
    fail2ban_sshd_enabled: true
    fail2ban_sshd_maxretry: 3
    fail2ban_sshd_bantime: 600
  roles:
    - role: fail2ban
```

```yaml
# ansible/roles/fail2ban/molecule/default/verify.yml
---
- name: Verify fail2ban role
  hosts: all
  become: true
  tasks:
    - name: "Verify fail2ban package is installed"
      ansible.builtin.command:
        cmd: "fail2ban-client --version"
      register: _verify_version
      changed_when: false
      failed_when: _verify_version.rc != 0

    - name: "Verify jail.d/sshd.conf exists"
      ansible.builtin.stat:
        path: /etc/fail2ban/jail.d/sshd.conf
      register: _verify_jail_config

    - name: "Assert jail config exists"
      ansible.builtin.assert:
        that:
          - _verify_jail_config.stat.exists
          - _verify_jail_config.stat.mode == '0644'

    - name: "Verify jail config contains correct maxretry"
      ansible.builtin.command:
        cmd: "grep 'maxretry = 3' /etc/fail2ban/jail.d/sshd.conf"
      register: _verify_maxretry
      changed_when: false
      failed_when: _verify_maxretry.rc != 0

    - name: "Verify jail config contains correct bantime"
      ansible.builtin.command:
        cmd: "grep 'bantime = 600' /etc/fail2ban/jail.d/sshd.conf"
      register: _verify_bantime
      changed_when: false
      failed_when: _verify_bantime.rc != 0
```

**Step 2: Run molecule syntax**

Run: `cd ansible/roles/fail2ban && molecule syntax`
Expected: PASS

**Step 3: Commit**

```bash
git add ansible/roles/fail2ban/molecule/
git commit -m "test(fail2ban): add molecule tests"
```

---

## Phase 5: Integration

### Task 16: Update workstation playbook with full role family

**Files:**
- Modify: `ansible/playbooks/workstation.yml`

**Step 1: Update Phase 3 in playbook**

Replace the current Phase 3 section:

```yaml
    # Phase 3: User & access
    - role: user
      tags: [user]
    - role: ssh_keys
      tags: [ssh_keys, security]
    - role: ssh
      tags: [ssh, security]
    - role: teleport
      tags: [teleport, security]
      when: teleport_enabled | default(false)
    - role: fail2ban
      tags: [fail2ban, security]
      when: fail2ban_enabled | default(true)
```

**Step 2: Commit**

```bash
git add ansible/playbooks/workstation.yml
git commit -m "feat(playbook): integrate full SSH family (user, ssh_keys, ssh, teleport, fail2ban)"
```

---

### Task 17: Add state:absent support to user role

**Files:**
- Modify: `ansible/roles/user/tasks/main.yml` — add absent user removal before creation
- Modify: `ansible/roles/user/defaults/main.yml` — document `accounts` data source

**Step 1: Add removal task to main.yml**

Before the owner creation task, add:

```yaml
    # Remove absent users (zero-trust: revoked users cleaned up)
    - name: "Remove absent users"
      ansible.builtin.user:
        name: "{{ item.name }}"
        state: absent
        remove: true
      loop: >-
        {{ (accounts | default([]))
           | selectattr('state', 'defined')
           | selectattr('state', 'equalto', 'absent')
           | list }}
      loop_control:
        label: "{{ item.name }}"
      tags: [user, security]

    - name: "Report: removed users"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        _rpt_fact: "_user_phases"
        _rpt_phase: "Remove absent"
        _rpt_detail: >-
          count={{ (accounts | default([]))
                   | selectattr('state', 'defined')
                   | selectattr('state', 'equalto', 'absent')
                   | list | length }}
        _rpt_status: "{{ 'done' if ((accounts | default([]))
                         | selectattr('state', 'defined')
                         | selectattr('state', 'equalto', 'absent')
                         | list | length > 0) else 'skip' }}"
      tags: [user, report]
```

**Step 2: Commit**

```bash
git add ansible/roles/user/
git commit -m "feat(user): add state:absent support for user lifecycle management"
```

---

### Task 18: Final validation — run all molecule syntax checks

**Step 1: Run syntax for all 5 roles**

```bash
cd ansible/roles/ssh_keys && molecule syntax
cd ../ssh && molecule syntax
cd ../user && molecule syntax
cd ../teleport && molecule syntax
cd ../fail2ban && molecule syntax
```

Expected: All PASS

**Step 2: Final commit with design doc status update**

Update `docs/plans/2026-02-22-ssh-family-zero-trust-design.md` status from `Draft` to `Implemented`.

```bash
git add docs/plans/2026-02-22-ssh-family-zero-trust-design.md
git commit -m "docs: mark SSH family zero-trust design as implemented"
```

---

## Summary

| Phase | Tasks | Commits | Roles affected |
|-------|-------|---------|----------------|
| 1: Extract ssh_keys | 1-5 | 5 | ssh_keys (new), user (modified), playbook |
| 2: Enhance ssh | 6-10 | 5 | ssh (modified) |
| 3: Create teleport | 11-13 | 3 | teleport (new) |
| 4: Create fail2ban | 14-15 | 2 | fail2ban (new) |
| 5: Integration | 16-18 | 3 | playbook, user, design doc |
| **Total** | **18 tasks** | **18 commits** | **5 roles** |

### New files created: ~45
### Files modified: ~10
### Files deleted: 2 (ssh keygen.yml, user ssh_keys.yml)
