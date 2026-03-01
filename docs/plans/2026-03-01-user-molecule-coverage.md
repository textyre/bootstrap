# user role — Full Molecule Coverage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close every verified gap between what the `user` role actually does and what molecule tests verify, so CI gives a true signal across Docker (Arch+Ubuntu) and Vagrant (arch-vm, ubuntu-base).

**Architecture:**
- Role bug fixed first (password_expire_warn dead variable) so tests can actually verify it
- Per-scenario variable strategy: `user_manage_password_aging` and `user_verify_root_lock` moved out of shared/converge.yml into per-scenario config (docker group_vars vs. vagrant/converge.yml vars)
- shared/converge.yml gains: `testuser_with_sudo` (sudo:true path), `accounts` list with absent user
- shared/verify.yml gains: shadow lock assertions, conditional password aging assertions, sudo:true check, absent-user check, full logrotate directive assertions

**Tech Stack:** Ansible molecule, Docker driver, Vagrant+libvirt driver, Python shadow database via `getent shadow`

---

## Gap Summary (what this plan fixes)

| Gap | Fix |
|-----|-----|
| `password_expire_warn` never set (dead var) | Add param to owner.yml + additional_users.yml |
| Shadow `!` (locked account) never verified | Add `getent shadow` + regex assertions in verify.yml |
| `user_manage_password_aging: false` everywhere | Vagrant: true; Docker: group_vars false |
| `password_warn_age` not in shadow (because param missing) | Fixed by role bug fix above |
| `user_verify_root_lock: false` everywhere | Vagrant: true (boxes lock root); Docker: false |
| `sudo: true` additional user path untested | Add testuser_with_sudo to converge + verify |
| `state: absent` user removal untested | Add testuser_toberemoved to prepare + converge + verify |
| Logrotate directives incomplete (4 missing) | Add assertions in verify.yml |

---

### Task 1: Fix role bug — add password_expire_warn

**Files:**
- Modify: `ansible/roles/user/tasks/owner.yml`
- Modify: `ansible/roles/user/tasks/additional_users.yml`

**Step 1: Edit owner.yml**

Add `password_expire_warn` after `password_expire_min` block:

```yaml
    password_expire_warn: >-
      {{ user_owner.password_warn_age | default(omit)
         if user_manage_password_aging | bool else omit }}
```

The full `ansible.builtin.user` task in owner.yml should end with:
```yaml
    password_expire_max: >-
      {{ user_owner.password_max_age | default(omit)
         if user_manage_password_aging | bool else omit }}
    password_expire_min: >-
      {{ user_owner.password_min_age | default(omit)
         if user_manage_password_aging | bool else omit }}
    password_expire_warn: >-
      {{ user_owner.password_warn_age | default(omit)
         if user_manage_password_aging | bool else omit }}
```

**Step 2: Edit additional_users.yml**

Same pattern using `item.password_warn_age`:

```yaml
    password_expire_warn: >-
      {{ item.password_warn_age | default(omit)
         if user_manage_password_aging | bool else omit }}
```

**Step 3: Commit**

```bash
cd /path/to/worktree
git add ansible/roles/user/tasks/owner.yml ansible/roles/user/tasks/additional_users.yml
git commit -m "fix(user): add password_expire_warn to owner and additional_users tasks"
```

---

### Task 2: Update shared/converge.yml — full coverage vars

**Files:**
- Modify: `ansible/roles/user/molecule/shared/converge.yml`

**Step 1: Replace converge.yml**

New content — remove `user_manage_password_aging` and `user_verify_root_lock` (moved to per-scenario), add `testuser_with_sudo`, add `accounts` with absent user:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Override owner to a test user (don't modify real running user)
    user_owner:
      name: testuser_owner
      shell: /bin/bash
      groups:
        - "{{ user_sudo_group }}"
      password_hash: ""
      update_password: on_create
      umask: "027"
      password_max_age: 365
      password_min_age: 1
      password_warn_age: 7
    user_additional_users:
      - name: testuser_extra
        shell: /bin/bash
        groups:
          - video
        sudo: false
        password_hash: ""
        update_password: on_create
        umask: "077"
        password_max_age: 90
        password_min_age: 0
        password_warn_age: 7
      - name: testuser_with_sudo
        shell: /bin/bash
        groups: []
        sudo: true
        password_hash: ""
        update_password: on_create
        umask: "077"
    # Users to remove (zero-trust cleanup)
    accounts:
      - name: testuser_toberemoved
        state: absent
    user_manage_umask: true
    user_sudo_logrotate_enabled: true
    user_sudo_log_input: false
    user_sudo_log_output: false

  roles:
    - role: user
```

Note: `user_manage_password_aging` and `user_verify_root_lock` are intentionally absent — they come from group_vars (Docker) or converge vars (Vagrant).

**Step 2: Commit**

```bash
git add ansible/roles/user/molecule/shared/converge.yml
git commit -m "test(user): expand shared converge with sudo:true user, absent user, aging vars"
```

---

### Task 3: Update vagrant/converge.yml — enable real production features

**Files:**
- Modify: `ansible/roles/user/molecule/vagrant/converge.yml`

**Step 1: Replace vagrant/converge.yml**

Same as shared but enables production-default features:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Override owner to a test user (don't modify real running user)
    user_owner:
      name: testuser_owner
      shell: /bin/bash
      groups:
        - "{{ user_sudo_group }}"
      password_hash: ""
      update_password: on_create
      umask: "027"
      password_max_age: 365
      password_min_age: 1
      password_warn_age: 7
    user_additional_users:
      - name: testuser_extra
        shell: /bin/bash
        groups:
          - video
        sudo: false
        password_hash: ""
        update_password: on_create
        umask: "077"
        password_max_age: 90
        password_min_age: 0
        password_warn_age: 7
      - name: testuser_with_sudo
        shell: /bin/bash
        groups: []
        sudo: true
        password_hash: ""
        update_password: on_create
        umask: "077"
    # Users to remove (zero-trust cleanup)
    accounts:
      - name: testuser_toberemoved
        state: absent
    user_manage_password_aging: true   # Real VMs support chage/shadow
    user_manage_umask: true
    user_verify_root_lock: true        # Vagrant boxes ship with locked root
    user_sudo_logrotate_enabled: true
    user_sudo_log_input: false
    user_sudo_log_output: false

  roles:
    - role: user
```

**Step 2: Commit**

```bash
git add ansible/roles/user/molecule/vagrant/converge.yml
git commit -m "test(user): enable password_aging and root_lock in vagrant converge"
```

---

### Task 4: Update docker/molecule.yml — group_vars for Docker-specific overrides

**Files:**
- Modify: `ansible/roles/user/molecule/docker/molecule.yml`

**Step 1: Add group_vars to provisioner section**

Add under `provisioner:`:

```yaml
provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    group_vars:
      all:
        user_manage_password_aging: false   # Docker: chage/shadow not reliable in containers
        user_verify_root_lock: false        # Docker: container root may not be locked
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
```

**Step 2: Commit**

```bash
git add ansible/roles/user/molecule/docker/molecule.yml
git commit -m "test(user): add docker group_vars for password_aging and root_lock flags"
```

---

### Task 5: Update prepare files — create testuser_toberemoved

**Files:**
- Modify: `ansible/roles/user/molecule/docker/prepare.yml`
- Modify: `ansible/roles/user/molecule/vagrant/prepare.yml`

**Step 1: Add to docker/prepare.yml**

Add at end:

```yaml
    - name: Create testuser_toberemoved (will be removed by role during converge)
      ansible.builtin.user:
        name: testuser_toberemoved
        state: present
        create_home: false
```

**Step 2: Add same task to vagrant/prepare.yml**

Same task appended at end.

**Step 3: Commit**

```bash
git add ansible/roles/user/molecule/docker/prepare.yml ansible/roles/user/molecule/vagrant/prepare.yml
git commit -m "test(user): create testuser_toberemoved in prepare so role can remove it"
```

---

### Task 6: Rewrite shared/verify.yml — full coverage

**Files:**
- Modify: `ansible/roles/user/molecule/shared/verify.yml`

This is the main task. Add the following new assertion blocks to the existing verify.yml.

**Step 1: After the existing "Owner: check shell" block (~line 40), add shadow lock check for owner:**

```yaml
    # ==========================================================
    # Owner shadow (account lock + password aging)
    # ==========================================================

    - name: "Owner shadow: get shadow entry"
      ansible.builtin.getent:
        database: shadow
        key: testuser_owner
      register: _user_verify_owner_shadow
      no_log: true

    - name: "Owner shadow: assert account is locked (password_hash empty → !)"
      ansible.builtin.assert:
        that:
          - _user_verify_owner_shadow.ansible_facts.getent_shadow['testuser_owner'][0] | regex_search('^[!*]')
        fail_msg: "testuser_owner shadow password field does not indicate locked account"

    - name: "Owner shadow: assert password_max_age in shadow"
      ansible.builtin.assert:
        that:
          - _user_verify_owner_shadow.ansible_facts.getent_shadow['testuser_owner'][3] | int == 365
        fail_msg: "testuser_owner shadow max_age not set to 365"
      when: user_manage_password_aging | bool

    - name: "Owner shadow: assert password_min_age in shadow"
      ansible.builtin.assert:
        that:
          - _user_verify_owner_shadow.ansible_facts.getent_shadow['testuser_owner'][2] | int == 1
        fail_msg: "testuser_owner shadow min_age not set to 1"
      when: user_manage_password_aging | bool

    - name: "Owner shadow: assert password_warn_age in shadow"
      ansible.builtin.assert:
        that:
          - _user_verify_owner_shadow.ansible_facts.getent_shadow['testuser_owner'][4] | int == 7
        fail_msg: "testuser_owner shadow warn_age not set to 7"
      when: user_manage_password_aging | bool
```

Shadow field indices:
- [0] = password hash (should start with `!` for locked)
- [2] = min days
- [3] = max days
- [4] = warn days

**Step 2: After the Extra user's umask assertions (~line 112), add Extra shadow checks and testuser_with_sudo:**

```yaml
    # ==========================================================
    # Extra user shadow (account lock + password aging)
    # ==========================================================

    - name: "Extra shadow: get shadow entry"
      ansible.builtin.getent:
        database: shadow
        key: testuser_extra
      register: _user_verify_extra_shadow
      no_log: true

    - name: "Extra shadow: assert account is locked"
      ansible.builtin.assert:
        that:
          - _user_verify_extra_shadow.ansible_facts.getent_shadow['testuser_extra'][0] | regex_search('^[!*]')
        fail_msg: "testuser_extra shadow password field does not indicate locked account"

    - name: "Extra shadow: assert password_max_age in shadow"
      ansible.builtin.assert:
        that:
          - _user_verify_extra_shadow.ansible_facts.getent_shadow['testuser_extra'][3] | int == 90
        fail_msg: "testuser_extra shadow max_age not set to 90"
      when: user_manage_password_aging | bool

    - name: "Extra shadow: assert password_min_age in shadow"
      ansible.builtin.assert:
        that:
          - _user_verify_extra_shadow.ansible_facts.getent_shadow['testuser_extra'][2] | int == 0
        fail_msg: "testuser_extra shadow min_age not set to 0"
      when: user_manage_password_aging | bool

    - name: "Extra shadow: assert password_warn_age in shadow"
      ansible.builtin.assert:
        that:
          - _user_verify_extra_shadow.ansible_facts.getent_shadow['testuser_extra'][4] | int == 7
        fail_msg: "testuser_extra shadow warn_age not set to 7"
      when: user_manage_password_aging | bool

    # ==========================================================
    # Additional user with sudo: true
    # ==========================================================

    - name: "Sudo user: check testuser_with_sudo exists"
      ansible.builtin.getent:
        database: passwd
        key: testuser_with_sudo
      register: _user_verify_with_sudo

    - name: "Sudo user: check testuser_with_sudo is in sudo group"
      ansible.builtin.command:
        cmd: "groups testuser_with_sudo"
      register: _user_verify_with_sudo_groups
      changed_when: false
      failed_when: "user_sudo_group not in _user_verify_with_sudo_groups.stdout"

    # ==========================================================
    # Absent user removed
    # ==========================================================

    - name: "Absent: verify testuser_toberemoved does not exist"
      ansible.builtin.command:
        cmd: "id testuser_toberemoved"
      register: _user_verify_absent
      changed_when: false
      failed_when: _user_verify_absent.rc == 0
```

**Step 3: In the Logrotate section, after existing assertions, add missing directive checks:**

```yaml
    - name: "Logrotate: assert delaycompress present"
      ansible.builtin.assert:
        that:
          - "'delaycompress' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'delaycompress' directive"

    - name: "Logrotate: assert missingok present"
      ansible.builtin.assert:
        that:
          - "'missingok' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'missingok' directive"

    - name: "Logrotate: assert notifempty present"
      ansible.builtin.assert:
        that:
          - "'notifempty' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'notifempty' directive"

    - name: "Logrotate: assert create directive present"
      ansible.builtin.assert:
        that:
          - "'create 0640 root adm' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'create 0640 root adm' directive"
```

**Step 4: Update the Summary debug message at the end to mention new checks.**

**Step 5: Commit**

```bash
git add ansible/roles/user/molecule/shared/verify.yml
git commit -m "test(user): add shadow lock, aging, sudo:true, absent user, logrotate directive assertions"
```

---

### Task 7: Push branch, open PR, monitor CI

**Step 1: Push**

```bash
git push -u origin fix/user-molecule-coverage
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "test(user): full molecule coverage — shadow, aging, sudo:true, absent, logrotate" \
  --body "..."
```

**Step 3: Monitor CI**

Watch all 3 environments:
- Docker (Arch-systemd + Ubuntu-systemd)
- Vagrant arch-vm
- Vagrant ubuntu-base

Expected outcomes:
- Docker: `user_manage_password_aging: false` → skip aging assertions; shadow lock check passes (containers lock accounts)
- Vagrant Arch: `user_manage_password_aging: true` → aging fields verified; `user_verify_root_lock: true` runs in converge
- Vagrant Ubuntu: same as Arch

**Step 4: If CI fails, debug using systematic-debugging skill**

---

### Task 8: Merge PR and cleanup

**Step 1: Merge**

```bash
gh pr merge --squash
```

**Step 2: Delete branch**

```bash
git push origin --delete fix/user-molecule-coverage
```

**Step 3: Remove worktree**

```bash
cd /path/to/main/repo
git worktree remove .worktrees/fix/user-molecule-coverage
```
