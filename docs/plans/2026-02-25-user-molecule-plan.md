# Plan: user role -- Molecule testing (shared + docker + vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Scope:** Add multi-scenario Molecule testing to `ansible/roles/user/`
**Reference roles:** `ntp/molecule/` (shared/docker/default pattern), `package_manager/molecule/` (vagrant/docker/shared pattern)

---

## 1. Current State

### What the role does

The `user` role manages the full user-account lifecycle on workstations:

| Phase | Task file | Description |
|-------|-----------|-------------|
| Preflight | `main.yml` | Assert OS in `_user_supported_os` |
| Vars | `main.yml` | Load `vars/<os_family>.yml` (package names) |
| Install | `install-<os>.yml` | Install sudo via `ansible.builtin.package` |
| Remove absent | `main.yml` | Remove users with `state: absent` from `accounts` list |
| Owner | `owner.yml` | Create primary owner, set groups/shell/password, deploy umask profile |
| Additional users | `additional_users.yml` | Loop over `user_additional_users`, optional sudo group |
| Sudo policy | `sudo.yml` | Deploy `/etc/sudoers.d/<group>` via `sudoers_hardening.j2` + logrotate |
| Security | `security.yml` | CIS 5.4.3: assert root password is locked (when `user_verify_root_lock`) |
| Verify | `verify.yml` (in-role) | Assert owner exists, in correct groups, sudoers valid, umask deployed |
| Report | `main.yml` | Phase reporting via `common` role |

### Key variables

| Variable | Default | Notes |
|----------|---------|-------|
| `user_owner` | dict with name/shell/groups/password_hash/umask/... | Primary admin account |
| `user_additional_users` | `[]` | List of extra user dicts |
| `user_sudo_group` | `wheel` (Arch) / `sudo` (Debian) | OS-aware |
| `user_sudo_timestamp_timeout` | `5` (base), `15` (developer), `0` (security) | Profile-aware |
| `user_sudo_use_pty` | `true` | CIS 5.3.5 |
| `user_sudo_logfile` | `/var/log/sudo.log` | CIS 5.3.7 |
| `user_sudo_logrotate_enabled` | `true` | Deploy logrotate config |
| `user_manage_umask` | `true` | Deploy `/etc/profile.d/umask-<user>.sh` |
| `user_manage_password_aging` | `true` | Set password_expire_max/min |
| `user_verify_root_lock` | `true` | CIS 5.4.3 root-lock assertion |

### Templates

| Template | Destination | Purpose |
|----------|-------------|---------|
| `sudoers_hardening.j2` | `/etc/sudoers.d/<group>` | Sudo policy (group ALL, timeout, use_pty, logfile, etc.) |
| `sudo_logrotate.j2` | `/etc/logrotate.d/sudo` | Logrotate for sudo.log |
| `user_umask.sh.j2` | `/etc/profile.d/umask-<user>.sh` | Per-user umask at login |

### Existing tests

**`molecule/default/`** -- localhost driver, Arch-only:

- `converge.yml`: Creates `testuser_owner` (wheel group, umask 027) + `Testuser_extra` (video group, no sudo). Disables password aging and root-lock check for container safety.
- `verify.yml`: 11 assertions checking user existence, group membership, umask values, sudoers file, visudo syntax, use_pty, logfile.
- `molecule.yml`: vault_password_file, localhost connection, test_sequence: syntax -> converge -> idempotence -> verify.

**Problems with current tests:**
1. Tests are Arch-only -- no cross-platform coverage.
2. Converge and verify are not in `shared/` -- cannot be reused by docker/vagrant scenarios.
3. No logrotate assertions in verify.
4. No test for `user_sudo_timestamp_timeout` value.
5. No test for `user_sudo_passwd_timeout` value.
6. Extra user name in converge is `Testuser_extra` (capital T) but verify checks `testuser_extra` (lowercase). This works because `ansible.builtin.user` lowercases on Linux, but it is confusing.
7. `accounts` variable (used in main.yml for absent-user removal) is not exercised at all.
8. No test for logrotate config at `/etc/logrotate.d/sudo`.
9. No test for `passwd_timeout` in sudoers.

### Dependencies on other roles

The `user` role depends on the `common` role for reporting (`report_phase.yml`, `report_render.yml`). In molecule docker/vagrant scenarios, `common` must be on `ANSIBLE_ROLES_PATH`, or `report` tags must be skipped.

---

## 2. GAP-01 Fix Plan: sudo logrotate

**Status: ALREADY FIXED.** The role already has:
- `templates/sudo_logrotate.j2` -- deployed to `/etc/logrotate.d/sudo`
- `tasks/sudo.yml` lines 14-24 -- conditionally deploys when `user_sudo_logrotate_enabled` and `user_sudo_logfile` is non-empty
- `defaults/main.yml` -- `user_sudo_logrotate_enabled: true`, `user_sudo_logrotate_frequency: "weekly"`, `user_sudo_logrotate_rotate: 13`

**What remains:** Add verification of the logrotate config in molecule verify.yml (see Section 7).

Template content (already deployed):
```jinja2
# {{ ansible_managed }}
{{ user_sudo_logfile }} {
    {{ user_sudo_logrotate_frequency }}
    rotate {{ user_sudo_logrotate_rotate }}
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
```

---

## 3. GAP-04 Fix Plan: sudoers hardening template

**Status: ALREADY FIXED.** The role already has:
- `templates/sudoers_hardening.j2` -- uses Jinja2 conditionals, not hardcoded values
- All sudo variables are defined in `defaults/main.yml`

Current template:
```jinja2
# {{ ansible_managed }}
%{{ user_sudo_group }} ALL=(ALL:ALL) ALL
Defaults timestamp_timeout={{ user_sudo_timestamp_timeout }}
{% if user_sudo_use_pty %}
Defaults use_pty
{% endif %}
{% if user_sudo_logfile | length > 0 %}
Defaults logfile="{{ user_sudo_logfile }}"
{% endif %}
{% if user_sudo_log_input %}
Defaults log_input
{% endif %}
{% if user_sudo_log_output %}
Defaults log_output
{% endif %}
{% if user_sudo_passwd_timeout is defined %}
Defaults passwd_timeout={{ user_sudo_passwd_timeout }}
{% endif %}
```

Current variable defaults:
```yaml
user_sudo_timestamp_timeout: >-  # profile-aware: 5 / 15 / 0
user_sudo_use_pty: true
user_sudo_logfile: "/var/log/sudo.log"
user_sudo_log_input: false
user_sudo_log_output: false
user_sudo_passwd_timeout: 1
```

**What remains:** Verify all template-driven values in molecule verify.yml (see Section 7).

---

## 4. Shared Migration

Move `converge.yml` and `verify.yml` from `molecule/default/` to `molecule/shared/` so they can be reused across default, docker, and vagrant scenarios.

### 4.1 New directory structure

```
ansible/roles/user/molecule/
  shared/
    converge.yml       # <-- moved from default/, made cross-platform
    verify.yml         # <-- moved from default/, made cross-platform
  default/
    molecule.yml       # points to ../shared/converge.yml + ../shared/verify.yml
  docker/
    molecule.yml
    prepare.yml
  vagrant/
    molecule.yml
    prepare.yml
```

### 4.2 Shared converge.yml

The shared converge must be cross-platform. Key changes from the current default converge:
1. Remove the `Assert test environment is Arch Linux` pre-task.
2. Use `user_sudo_group` (auto-detects wheel vs sudo) instead of hardcoding `wheel`.
3. Keep vault_password_file for localhost scenario (docker/vagrant don't need vault).
4. Fix the `Testuser_extra` -> `testuser_extra` naming inconsistency.

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
    user_manage_password_aging: false   # may not work in containers
    user_manage_umask: true
    user_verify_root_lock: false        # root may not be locked in test environments
    user_sudo_logrotate_enabled: true
    user_sudo_log_input: false
    user_sudo_log_output: false

  roles:
    - role: user
```

### 4.3 Shared verify.yml

See Section 7 for the full verify.yml design.

### 4.4 Updated default molecule.yml

```yaml
---
driver:
  name: default
  options:
    managed: false

platforms:
  - name: Localhost

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
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
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

---

## 5. Docker Scenario

User creation, sudo configuration, and logrotate all work fine in systemd containers. The `common` role must be available (for reporting tasks) or `report` tag must be skipped.

### 5.1 molecule/docker/molecule.yml

```yaml
---
driver:
  name: docker

platforms:
  - name: Archlinux-systemd
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/bootstrap/arch-systemd:latest}"
    pre_build_image: true
    command: /usr/lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    privileged: true
    dns_servers:
      - 8.8.8.8
      - 8.8.4.4

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

### 5.2 molecule/docker/prepare.yml

The container needs an updated pacman cache and `logrotate` installed (not present by default in the arch-systemd image). Also ensure `shadow` utils are available for `getent shadow`.

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true

    - name: Ensure logrotate is installed (for sudo logrotate test)
      ansible.builtin.package:
        name: logrotate
        state: present
```

### 5.3 Docker-specific considerations

| Concern | Mitigation |
|---------|------------|
| `getent shadow` may fail if `/etc/shadow` permissions are non-standard in container | `user_verify_root_lock: false` in converge disables the root lock check |
| `password_expire_max/min` may not be supported in containers without real PAM | `user_manage_password_aging: false` in converge |
| `visudo` must exist in container | The role installs `sudo` package which includes `visudo` |
| `accounts` absent-user removal runs but has no users to remove (empty default) | Safe no-op |
| `common` role for reporting | Skipped via `skip-tags: report` |

---

## 6. Vagrant Scenario

Vagrant VMs provide full OS environments with real PAM, real shadow, real systemd. This enables testing features that containers cannot: password aging, root lock verification, full sudo -l validation.

### 6.1 molecule/vagrant/molecule.yml

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: generic/arch
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: bento/ubuntu-24.04
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  options:
    skip-tags: report
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  inventory:
    host_vars:
      localhost:
        ansible_python_interpreter: "{{ ansible_playbook_python }}"
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

### 6.2 molecule/vagrant/prepare.yml

Vagrant boxes need package cache refresh and keyring fixes (Arch generic/arch has stale keys). Ubuntu needs apt cache update. Also install logrotate on both.

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Bootstrap Python on Arch (raw -- no Python required)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts
      ansible.builtin.gather_facts:

    - name: Refresh pacman keyring on Arch (generic/arch box has stale keys)
      ansible.builtin.shell: |
        sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
        pacman -Sy --noconfirm archlinux-keyring
        sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
        pacman-key --populate archlinux
      args:
        executable: /bin/bash
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade on Arch
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Ensure logrotate is installed (Arch)
      ansible.builtin.package:
        name: logrotate
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

### 6.3 Cross-platform considerations: wheel vs sudo group

| OS | Sudo group | Sudoers file path | visudo path |
|----|-----------|-------------------|-------------|
| Arch Linux | `wheel` | `/etc/sudoers.d/wheel` | `/usr/sbin/visudo` |
| Ubuntu 24.04 | `sudo` | `/etc/sudoers.d/sudo` | `/usr/sbin/visudo` |

The role auto-detects via `user_sudo_group` in defaults:
```yaml
user_sudo_group: "{{ 'sudo' if ansible_facts['os_family'] == 'Debian' else 'wheel' }}"
```

The shared verify.yml must use `user_sudo_group` variable (not hardcoded `wheel`) for all assertions. See Section 7.

### 6.4 Vagrant-specific features to test (beyond docker)

These can be enabled in a vagrant-specific converge override or tested in verify with `when` guards:

| Feature | Docker | Vagrant | Notes |
|---------|--------|---------|-------|
| Password aging (`password_expire_max/min`) | Skip | Test | Real `/etc/shadow` and `chage` in VMs |
| Root lock verification (`user_verify_root_lock`) | Skip | Test | Real shadow entries in VMs |
| `sudo -l` output validation | Risky | Test | Full PAM stack available in VMs |
| logrotate config parsing | Test | Test | Both environments have filesystem |

**Note:** The shared converge.yml disables `user_manage_password_aging` and `user_verify_root_lock` for safety in containers. For vagrant, we could override these, but the simpler approach is to keep the shared converge as-is (safe for all environments) and add vagrant-specific verify assertions that test the resulting state even when these features are disabled at converge time.

---

## 7. Verify.yml Design

### 7.1 Full shared verify.yml

The verify playbook loads role defaults for variable access and uses `when` blocks for cross-platform assertions.

```yaml
---
- name: Verify user role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "../../defaults/main.yml"

  tasks:

    # ==========================================================
    # Owner user
    # ==========================================================

    - name: "Owner: check user exists in passwd"
      ansible.builtin.getent:
        database: passwd
        key: testuser_owner
      register: _user_verify_owner
      failed_when: _user_verify_owner is failed

    - name: "Owner: check user is in sudo group"
      ansible.builtin.command:
        cmd: "groups testuser_owner"
      register: _user_verify_owner_groups
      changed_when: false
      failed_when: "user_sudo_group not in _user_verify_owner_groups.stdout"

    - name: "Owner: check home directory exists"
      ansible.builtin.stat:
        path: /home/testuser_owner
      register: _user_verify_owner_home
      failed_when: not _user_verify_owner_home.stat.exists

    - name: "Owner: check shell is /bin/bash"
      ansible.builtin.command:
        cmd: "getent passwd testuser_owner"
      register: _user_verify_owner_shell
      changed_when: false
      failed_when: "':/bin/bash' not in _user_verify_owner_shell.stdout"

    # ==========================================================
    # Owner umask
    # ==========================================================

    - name: "Umask: check profile script deployed for owner"
      ansible.builtin.stat:
        path: /etc/profile.d/umask-testuser_owner.sh
      register: _user_verify_umask_stat
      failed_when: not _user_verify_umask_stat.stat.exists

    - name: "Umask: read profile script content"
      ansible.builtin.slurp:
        src: /etc/profile.d/umask-testuser_owner.sh
      register: _user_verify_umask_raw

    - name: "Umask: set text fact"
      ansible.builtin.set_fact:
        _user_verify_umask_text: "{{ _user_verify_umask_raw.content | b64decode }}"

    - name: "Umask: assert value is 027"
      ansible.builtin.assert:
        that:
          - "'umask 027' in _user_verify_umask_text"
        fail_msg: "Owner umask profile does not contain 'umask 027'"

    - name: "Umask: assert Ansible managed marker"
      ansible.builtin.assert:
        that:
          - "'Ansible' in _user_verify_umask_text"
        fail_msg: "Owner umask profile missing Ansible managed marker"

    # ==========================================================
    # Additional user
    # ==========================================================

    - name: "Extra: check user exists"
      ansible.builtin.getent:
        database: passwd
        key: testuser_extra
      register: _user_verify_extra
      failed_when: _user_verify_extra is failed

    - name: "Extra: check user is NOT in sudo group"
      ansible.builtin.command:
        cmd: "groups testuser_extra"
      register: _user_verify_extra_groups
      changed_when: false
      failed_when: "user_sudo_group in _user_verify_extra_groups.stdout"

    - name: "Extra: check user is in video group"
      ansible.builtin.assert:
        that:
          - "'video' in _user_verify_extra_groups.stdout"
        fail_msg: "Extra user testuser_extra is not in video group"

    - name: "Extra: check umask profile deployed"
      ansible.builtin.stat:
        path: /etc/profile.d/umask-testuser_extra.sh
      register: _user_verify_extra_umask
      failed_when: not _user_verify_extra_umask.stat.exists

    - name: "Extra: read umask profile"
      ansible.builtin.slurp:
        src: /etc/profile.d/umask-testuser_extra.sh
      register: _user_verify_extra_umask_raw

    - name: "Extra: assert umask is 077"
      ansible.builtin.assert:
        that:
          - "'umask 077' in (_user_verify_extra_umask_raw.content | b64decode)"
        fail_msg: "Extra user umask profile does not contain 'umask 077'"

    # ==========================================================
    # Sudoers policy
    # ==========================================================

    - name: "Sudoers: check file exists"
      ansible.builtin.stat:
        path: "/etc/sudoers.d/{{ user_sudo_group }}"
      register: _user_verify_sudoers_stat

    - name: "Sudoers: assert file exists with correct permissions"
      ansible.builtin.assert:
        that:
          - _user_verify_sudoers_stat.stat.exists
          - _user_verify_sudoers_stat.stat.mode == '0440'
          - _user_verify_sudoers_stat.stat.pw_name == 'root'
        fail_msg: >-
          /etc/sudoers.d/{{ user_sudo_group }} missing or wrong permissions
          (expected root 0440)

    - name: "Sudoers: validate syntax with visudo"
      ansible.builtin.command:
        cmd: "/usr/sbin/visudo -cf /etc/sudoers.d/{{ user_sudo_group }}"
      register: _user_verify_sudoers_syntax
      changed_when: false
      failed_when: _user_verify_sudoers_syntax.rc != 0

    - name: "Sudoers: read file content"
      ansible.builtin.slurp:
        src: "/etc/sudoers.d/{{ user_sudo_group }}"
      register: _user_verify_sudoers_raw

    - name: "Sudoers: set text fact"
      ansible.builtin.set_fact:
        _user_verify_sudoers_text: "{{ _user_verify_sudoers_raw.content | b64decode }}"

    - name: "Sudoers: assert group ALL rule present"
      ansible.builtin.assert:
        that:
          - "'%' ~ user_sudo_group ~ ' ALL=(ALL:ALL) ALL' in _user_verify_sudoers_text"
        fail_msg: "Sudoers file missing group ALL rule for %{{ user_sudo_group }}"

    - name: "Sudoers: assert timestamp_timeout present"
      ansible.builtin.assert:
        that:
          - "'timestamp_timeout=' in _user_verify_sudoers_text"
        fail_msg: "Sudoers file missing timestamp_timeout directive"

    - name: "Sudoers: assert use_pty present"
      ansible.builtin.assert:
        that:
          - "'use_pty' in _user_verify_sudoers_text"
        fail_msg: "Sudoers file missing use_pty directive"

    - name: "Sudoers: assert logfile present"
      ansible.builtin.assert:
        that:
          - "'logfile=\"/var/log/sudo.log\"' in _user_verify_sudoers_text"
        fail_msg: "Sudoers file missing logfile directive"

    - name: "Sudoers: assert passwd_timeout present"
      ansible.builtin.assert:
        that:
          - "'passwd_timeout=' in _user_verify_sudoers_text"
        fail_msg: "Sudoers file missing passwd_timeout directive"

    - name: "Sudoers: assert Ansible managed marker"
      ansible.builtin.assert:
        that:
          - "'Ansible' in _user_verify_sudoers_text"
        fail_msg: "Sudoers file missing Ansible managed marker"

    # ==========================================================
    # Logrotate for sudo.log
    # ==========================================================

    - name: "Logrotate: check config exists"
      ansible.builtin.stat:
        path: /etc/logrotate.d/sudo
      register: _user_verify_logrotate_stat

    - name: "Logrotate: assert config exists with correct permissions"
      ansible.builtin.assert:
        that:
          - _user_verify_logrotate_stat.stat.exists
          - _user_verify_logrotate_stat.stat.mode == '0644'
          - _user_verify_logrotate_stat.stat.pw_name == 'root'
        fail_msg: >-
          /etc/logrotate.d/sudo missing or wrong permissions
          (expected root 0644)

    - name: "Logrotate: read config content"
      ansible.builtin.slurp:
        src: /etc/logrotate.d/sudo
      register: _user_verify_logrotate_raw

    - name: "Logrotate: set text fact"
      ansible.builtin.set_fact:
        _user_verify_logrotate_text: "{{ _user_verify_logrotate_raw.content | b64decode }}"

    - name: "Logrotate: assert sudo.log path in config"
      ansible.builtin.assert:
        that:
          - "'/var/log/sudo.log' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing /var/log/sudo.log path"

    - name: "Logrotate: assert weekly rotation"
      ansible.builtin.assert:
        that:
          - "'weekly' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'weekly' directive"

    - name: "Logrotate: assert rotate count"
      ansible.builtin.assert:
        that:
          - "'rotate 13' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'rotate 13' directive"

    - name: "Logrotate: assert compress enabled"
      ansible.builtin.assert:
        that:
          - "'compress' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing 'compress' directive"

    - name: "Logrotate: assert Ansible managed marker"
      ansible.builtin.assert:
        that:
          - "'Ansible' in _user_verify_logrotate_text"
        fail_msg: "Logrotate config missing Ansible managed marker"

    # ==========================================================
    # Sudo package installed
    # ==========================================================

    - name: "Package: gather package facts"
      ansible.builtin.package_facts:
        manager: auto

    - name: "Package: assert sudo is installed"
      ansible.builtin.assert:
        that:
          - "'sudo' in ansible_facts.packages"
        fail_msg: "sudo package not found in installed packages"

    # ==========================================================
    # Cross-platform: Arch-specific checks
    # ==========================================================

    - name: "Arch-only: verify sudoers file at /etc/sudoers.d/wheel"
      ansible.builtin.assert:
        that:
          - "'%wheel' in _user_verify_sudoers_text"
        fail_msg: "Arch sudoers file does not contain %wheel rule"
      when: ansible_facts['os_family'] == 'Archlinux'

    # ==========================================================
    # Cross-platform: Debian-specific checks
    # ==========================================================

    - name: "Debian-only: verify sudoers file at /etc/sudoers.d/sudo"
      ansible.builtin.assert:
        that:
          - "'%sudo' in _user_verify_sudoers_text"
        fail_msg: "Debian sudoers file does not contain %sudo rule"
      when: ansible_facts['os_family'] == 'Debian'

    # ==========================================================
    # Summary
    # ==========================================================

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          user role verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}:
          owner user exists, correct groups, umask deployed,
          extra user exists with correct groups,
          sudoers policy valid ({{ user_sudo_group }}),
          logrotate config deployed, sudo package installed.
```

### 7.2 Assertion summary table

| # | Assertion | Cross-platform | Arch-only | Debian-only |
|---|-----------|:-:|:-:|:-:|
| 1 | Owner user exists in passwd | x | | |
| 2 | Owner is in sudo group | x | | |
| 3 | Owner home directory exists | x | | |
| 4 | Owner shell is /bin/bash | x | | |
| 5 | Owner umask profile deployed | x | | |
| 6 | Owner umask value is 027 | x | | |
| 7 | Owner umask has Ansible marker | x | | |
| 8 | Extra user exists | x | | |
| 9 | Extra user NOT in sudo group | x | | |
| 10 | Extra user IS in video group | x | | |
| 11 | Extra user umask profile deployed | x | | |
| 12 | Extra user umask is 077 | x | | |
| 13 | Sudoers file exists (0440, root) | x | | |
| 14 | Sudoers syntax valid (visudo) | x | | |
| 15 | Sudoers group ALL rule | x | | |
| 16 | Sudoers timestamp_timeout present | x | | |
| 17 | Sudoers use_pty present | x | | |
| 18 | Sudoers logfile present | x | | |
| 19 | Sudoers passwd_timeout present | x | | |
| 20 | Sudoers Ansible managed marker | x | | |
| 21 | Logrotate config exists (0644, root) | x | | |
| 22 | Logrotate has sudo.log path | x | | |
| 23 | Logrotate weekly directive | x | | |
| 24 | Logrotate rotate 13 | x | | |
| 25 | Logrotate compress enabled | x | | |
| 26 | Logrotate Ansible managed marker | x | | |
| 27 | sudo package installed | x | | |
| 28 | Sudoers contains %wheel | | x | |
| 29 | Sudoers contains %sudo | | | x |

Total: 29 assertions (27 cross-platform + 2 OS-specific).

---

## 8. Implementation Order

### Step 1: Create `molecule/shared/` directory and move playbooks

```bash
mkdir -p ansible/roles/user/molecule/shared
```

Write `molecule/shared/converge.yml` (Section 4.2 content).
Write `molecule/shared/verify.yml` (Section 7.1 content).

### Step 2: Update `molecule/default/molecule.yml`

Replace the current converge/verify paths with `../shared/` references (Section 4.4).
Delete the old `molecule/default/converge.yml` and `molecule/default/verify.yml`.

### Step 3: Run default scenario to confirm shared migration works

```bash
# On remote VM:
cd ansible/roles/user
molecule test -s default
```

Expected: syntax -> converge -> idempotence -> verify all pass.

### Step 4: Create docker scenario

Write `molecule/docker/molecule.yml` (Section 5.1).
Write `molecule/docker/prepare.yml` (Section 5.2).

### Step 5: Run docker scenario

```bash
cd ansible/roles/user
molecule test -s docker
```

Expected: syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy all pass.

### Step 6: Create vagrant scenario

Write `molecule/vagrant/molecule.yml` (Section 6.1).
Write `molecule/vagrant/prepare.yml` (Section 6.2).

### Step 7: Run vagrant scenario

```bash
cd ansible/roles/user
molecule test -s vagrant
```

Expected: Both `arch-vm` and `ubuntu-noble` platforms pass all assertions.
The Debian-specific assertions (sudoers contains %sudo) activate on Ubuntu.
The Arch-specific assertions (sudoers contains %wheel) activate on Arch.

### Step 8: Run ansible-lint

```bash
ansible-lint ansible/roles/user/
```

Fix any findings.

### Step 9: Commit

```bash
git add ansible/roles/user/molecule/
git commit -m "test(user): add shared/docker/vagrant molecule scenarios with 29 cross-platform assertions"
```

---

## 9. Risks / Notes

### 9.1 Sudo testing in containers

| Risk | Impact | Mitigation |
|------|--------|------------|
| `requiretty` may be set in base sudoers | Prevents `sudo -l` from working non-interactively | Do not use `sudo -l` in verify (use file content assertions instead) |
| `getent shadow` requires root or shadow group | May fail for unprivileged test runners | Verify runs with `become: true` |
| `password_expire_max/min` silently ignored in containers | No real `/etc/shadow` aging mechanism | Disabled via `user_manage_password_aging: false` in converge; vagrant tests can verify this |
| Container may not have `logrotate` package | `/etc/logrotate.d/sudo` deployed but logrotate binary absent | Install logrotate in `prepare.yml` |

### 9.2 wheel vs sudo group cross-platform

The `user_sudo_group` variable auto-detects based on `ansible_facts['os_family']`:
- Archlinux -> `wheel`
- Debian -> `sudo`

The shared converge uses `"{{ user_sudo_group }}"` in the owner's groups list. The shared verify uses `user_sudo_group` for all sudoers path assertions. This ensures correct behavior on both platforms without any hardcoded group names.

**Edge case:** The `video` group used for `testuser_extra` must exist on both platforms. On Arch Linux, `video` exists by default. On Ubuntu 24.04, `video` also exists by default. If a future platform does not have it, the `ansible.builtin.user` module will fail at converge time (not a silent error).

### 9.3 common role dependency

The `user` role uses `include_role: common` for reporting. In docker and vagrant scenarios, `ANSIBLE_ROLES_PATH` is set to `${MOLECULE_PROJECT_DIRECTORY}/../` (the roles directory), which makes the `common` role available. However, `skip-tags: report` is also set in provisioner options as a safety measure -- if the common role is not available or has issues, the report tasks are simply skipped.

### 9.4 `accounts` variable (absent-user removal)

The `main.yml` orchestrator references `accounts | default([])` for removing absent users. This variable is not set in the molecule converge, so it defaults to an empty list and the removal loop is a no-op. Testing absent-user removal would require:
1. Adding a user in prepare
2. Adding that user to `accounts` with `state: absent` in converge
3. Asserting the user no longer exists in verify

This is deferred to a future enhancement as it is orthogonal to the core molecule migration.

### 9.5 `_user_supported_os` private variable

The `tasks/main.yml` references `_user_supported_os` (underscore-prefixed) but `defaults/main.yml` defines `user_supported_os` (no underscore). The role redesign plan (2026-02-22) specified `_user_supported_os` as a private var. The current code uses `user_supported_os` in defaults. This mismatch needs to be resolved before or during this work:
- Either rename the defaults variable to `_user_supported_os` (move to vars/main.yml since private vars should not be in defaults), or
- Update main.yml to reference `user_supported_os`.

This should be a pre-requisite fix before the molecule work begins.

### 9.6 Template variable naming inconsistency

The `user_umask.sh.j2` template references `{{ _umask_user }}` and `{{ _umask_value }}` (underscore-prefixed), but `owner.yml` passes them as `umask_user` and `umask_value` (no underscore):

```yaml
# owner.yml (current)
  vars:
    umask_user: "{{ user_owner.name }}"
    umask_value: "{{ user_owner.umask | default('027') }}"
```

The template expects `_umask_user` / `_umask_value`. This is either already broken in production (template rendering with undefined vars) or the underscore-prefixed names are mapped somewhere else. Verify this works in the default scenario before migrating to shared -- if it fails, fix the template/task variable names to match.

### 9.7 Idempotence considerations

The `idempotence` step in the test sequence reruns converge and expects zero changes. Potential idempotence issues:
- `ansible.builtin.user` with `password: ""` and `update_password: on_create` should be idempotent.
- `ansible.builtin.template` tasks are idempotent by nature (no change if content matches).
- `ansible.builtin.package` with `state: present` is idempotent.

If idempotence fails, investigate which task reports "changed" on the second run and fix accordingly.

### 9.8 Vagrant box availability

`generic/arch` and `bento/ubuntu-24.04` must be available on the test machine. The vagrant scenario depends on libvirt provider being configured. If KVM is not available, vagrant tests will fail with a provider error. This is consistent with the `package_manager` role's vagrant scenario.
