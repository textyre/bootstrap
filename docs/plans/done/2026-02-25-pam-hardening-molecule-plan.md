# pam_hardening role -- Molecule testing plan

**Date:** 2026-02-25
**Status:** Draft
**Depends on:** 2026-02-21-pam-hardening-refactor-design.md (implemented)

---

## 1. Current State

### Role overview

The `pam_hardening` role deploys PAM faillock brute-force protection across four platform families:

| Platform    | os_family    | PAM stack method                                    |
|-------------|-------------|-----------------------------------------------------|
| Arch Linux  | `Archlinux` | `lineinfile` in `/etc/pam.d/system-auth`            |
| Void Linux  | `Void`      | `lineinfile` in `/etc/pam.d/system-auth` (same)     |
| Ubuntu/Deb  | `Debian`    | `pam-auth-update --package` with two profile files   |
| Fedora      | `RedHat`    | `authselect enable-feature with-faillock`            |

The role writes `/etc/security/faillock.conf` (cross-platform template) and then dispatches to platform-specific task files that activate faillock in the PAM stack.

### File inventory

```
ansible/roles/pam_hardening/
  defaults/main.yml              # 11 variables, all pam_hardening_faillock_* prefixed
  handlers/main.yml              # 2 handlers: Update PAM (Debian), Apply authselect (RedHat)
  meta/main.yml                  # platforms: Arch, Debian, Ubuntu, Fedora; deps: []
  tasks/
    main.yml                     # include faillock.yml when pam_hardening_faillock_enabled
    faillock.yml                 # template faillock.conf + 3 platform dispatchers
    faillock_arch.yml            # 3x lineinfile into /etc/pam.d/system-auth
    faillock_debian.yml          # 2x copy to /usr/share/pam-configs/ + notify handler
    faillock_redhat.yml          # authselect enable-feature with-faillock
  templates/
    faillock.conf.j2             # 22-line template with conditional directives
  molecule/default/
    molecule.yml                 # driver: default (localhost), vault_password_file, test_sequence: syntax/converge/verify
    converge.yml                 # loads vault.yml, applies pam_hardening role
    verify.yml                   # 7 tasks: stat faillock.conf, slurp+assert deny/unlock_time/even_deny_root, Debian profile checks
```

### Existing test coverage

The current `molecule/default/` scenario runs on **localhost only** (the developer's Arch workstation). It verifies:

- `/etc/security/faillock.conf` exists
- Contains `deny =` and `unlock_time =` directives
- Contains `even_deny_root` directive (bare line)
- Debian-only: checks `/usr/share/pam-configs/faillock` and `faillock-authfail` exist

**Gaps:**
- No Docker container testing (no isolated environment)
- No Ubuntu/Debian testing (Debian assertions are skipped on Arch localhost)
- No Vagrant VM testing (no real PAM stack validation)
- No assertion that PAM stack files (`/etc/pam.d/system-auth`) contain faillock lines
- No idempotence check in test_sequence
- vault.yml loaded in converge/verify but role uses zero vault variables (unnecessary boilerplate)
- `fail_interval` and `root_unlock_time` not verified in faillock.conf assertions
- No `audit` directive verification in faillock.conf

---

## 2. Cross-Platform PAM Plan

### faillock.conf (universal)

`/etc/security/faillock.conf` has an identical format on all Linux distributions. The template `faillock.conf.j2` requires no platform branching. Verifying this file is the same on every platform.

### PAM stack integration (platform-specific)

| Platform | PAM file(s) modified | What to verify |
|----------|---------------------|----------------|
| Arch/Void | `/etc/pam.d/system-auth` | Contains 3 lines: `pam_faillock.so preauth`, `pam_faillock.so authfail`, `pam_faillock.so` (account) |
| Debian/Ubuntu | `/usr/share/pam-configs/faillock`, `/usr/share/pam-configs/faillock-authfail` | Both profile files exist with correct content; `pam-auth-update --package` was called (handler) |
| Fedora | authselect state | `authselect current` output includes `with-faillock` feature |

### Key difference: Docker vs Vagrant testing

- **Docker (Arch systemd container):** Can verify file deployment and PAM file content. Cannot test actual login-based faillock behavior (no real login sessions in containers). Sufficient for config correctness.
- **Vagrant (Arch + Ubuntu VMs):** Can verify file deployment AND test that `faillock` command actually works after applying the role. Can attempt SSH login with wrong password and observe lockout (stretch goal, not required for first iteration).

---

## 3. Missing Variables

The role already addresses all variables from the original CRIT-04 and MED-01 findings. Current `defaults/main.yml` includes:

| Variable | Current default | Status |
|----------|----------------|--------|
| `pam_hardening_faillock_enabled` | `true` | Implemented (MED-01 fix) |
| `pam_hardening_faillock_deny` | `3` | Implemented |
| `pam_hardening_faillock_fail_interval` | `900` | Implemented |
| `pam_hardening_faillock_unlock_time` | `900` | Implemented |
| `pam_hardening_faillock_root_unlock_time` | `900` | Implemented |
| `pam_hardening_faillock_audit` | `true` | Implemented |
| `pam_hardening_faillock_silent` | `false` | Implemented |
| `pam_hardening_faillock_even_deny_root` | `true` | Implemented |
| `pam_hardening_faillock_local_users_only` | `false` | Implemented |
| `pam_hardening_faillock_nodelay` | `false` | Implemented |
| `pam_hardening_faillock_x11_skip` | `false` | Implemented |

No new variables are needed for molecule testing. The verify playbook should assert against the default values above.

---

## 4. Docker Scenario

### Purpose

Isolated Arch Linux container test: verifies faillock.conf deployment, PAM stack file modifications via lineinfile, and idempotence. Does NOT test actual login lockout behavior.

### molecule/docker/molecule.yml

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

### molecule/docker/prepare.yml

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
```

### PAM testing limitations in Docker

The Arch systemd container has `/etc/pam.d/system-auth` present (part of the `pam` package in the base image). The `lineinfile` tasks will succeed and modify the file. However:

- No real login daemon (sshd, login) is running, so faillock cannot be exercised through actual authentication
- `faillock` CLI utility may not be installed by default (it is part of `pam` on Arch, so it should be present)
- Verify assertions should focus on **file content** (faillock.conf values, system-auth lines), not login behavior

---

## 5. Vagrant Scenario

### Purpose

Full VM testing on Arch Linux and Ubuntu 24.04. Verifies faillock.conf deployment, PAM stack integration for both platform families, and idempotence. Optionally can verify actual faillock behavior via SSH login attempts.

### molecule/vagrant/molecule.yml

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

### molecule/vagrant/prepare.yml

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

    - name: Full system upgrade on Arch (ensures pam/openssl compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

Note: The vagrant prepare.yml is copied from the `package_manager` role's vagrant scenario, which is the established pattern for dual-platform Vagrant testing.

---

## 6. Shared Migration

### Current structure (to be replaced)

```
molecule/default/
  molecule.yml     # localhost driver + vault
  converge.yml     # loads vault, applies role
  verify.yml       # 7 assertion tasks
```

### Target structure

```
molecule/
  shared/
    converge.yml   # no vault (role uses no vault vars)
    verify.yml     # expanded assertions with platform guards
  default/
    molecule.yml   # localhost driver, points to ../shared/*
  docker/
    molecule.yml   # docker driver, points to ../shared/*
    prepare.yml    # pacman -Sy
  vagrant/
    molecule.yml   # vagrant/libvirt driver, points to ../shared/*
    prepare.yml    # keyring refresh + apt cache
```

### shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: pam_hardening
```

Key change from current: **vault.yml removed**. The pam_hardening role does not reference any vault variables. The current converge loads vault.yml as inherited boilerplate from other roles -- this is unnecessary.

### default/molecule.yml

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

Changes from current:
- `vault_password_file` removed (not needed)
- `playbooks` point to `../shared/`
- `idempotence` added to test_sequence

---

## 7. Verify.yml Design

### Assertion categories

1. **faillock.conf content** (all platforms)
2. **faillock.conf permissions** (all platforms)
3. **PAM stack files -- Arch/Void** (when os_family in Archlinux, Void)
4. **PAM profile files -- Debian/Ubuntu** (when os_family == Debian)
5. **authselect state -- Fedora** (when os_family == RedHat)
6. **Diagnostic output** (informational, no assertions)

### shared/verify.yml

```yaml
---
- name: Verify pam_hardening role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- faillock.conf existence and permissions ----

    - name: Stat /etc/security/faillock.conf
      ansible.builtin.stat:
        path: /etc/security/faillock.conf
      register: pam_hardening_verify_conf

    - name: Assert faillock.conf exists with correct owner and mode
      ansible.builtin.assert:
        that:
          - pam_hardening_verify_conf.stat.exists
          - pam_hardening_verify_conf.stat.isreg
          - pam_hardening_verify_conf.stat.pw_name == 'root'
          - pam_hardening_verify_conf.stat.gr_name == 'root'
          - pam_hardening_verify_conf.stat.mode == '0644'
        fail_msg: >-
          /etc/security/faillock.conf missing or wrong permissions
          (expected root:root 0644)

    # ---- faillock.conf content ----

    - name: Slurp faillock.conf
      ansible.builtin.slurp:
        src: /etc/security/faillock.conf
      register: pam_hardening_verify_conf_raw

    - name: Set faillock.conf text fact
      ansible.builtin.set_fact:
        pam_hardening_verify_conf_text: >-
          {{ pam_hardening_verify_conf_raw.content | b64decode }}

    - name: Assert faillock.conf deny setting matches default
      ansible.builtin.assert:
        that:
          - >-
            pam_hardening_verify_conf_text is search(
            'deny = ' ~ pam_hardening_faillock_deny | string)
        fail_msg: >-
          faillock.conf deny value does not match expected
          {{ pam_hardening_faillock_deny }}

    - name: Assert faillock.conf fail_interval setting
      ansible.builtin.assert:
        that:
          - >-
            pam_hardening_verify_conf_text is search(
            'fail_interval = ' ~ pam_hardening_faillock_fail_interval | string)
        fail_msg: >-
          faillock.conf fail_interval does not match expected
          {{ pam_hardening_faillock_fail_interval }}

    - name: Assert faillock.conf unlock_time setting
      ansible.builtin.assert:
        that:
          - >-
            pam_hardening_verify_conf_text is search(
            'unlock_time = ' ~ pam_hardening_faillock_unlock_time | string)
        fail_msg: >-
          faillock.conf unlock_time does not match expected
          {{ pam_hardening_faillock_unlock_time }}

    - name: Assert faillock.conf root_unlock_time setting
      ansible.builtin.assert:
        that:
          - >-
            pam_hardening_verify_conf_text is search(
            'root_unlock_time = ' ~ pam_hardening_faillock_root_unlock_time | string)
        fail_msg: >-
          faillock.conf root_unlock_time does not match expected
          {{ pam_hardening_faillock_root_unlock_time }}

    - name: Assert faillock.conf even_deny_root directive present
      ansible.builtin.assert:
        that:
          - pam_hardening_verify_conf_text is search('(?m)^even_deny_root$')
        fail_msg: >-
          faillock.conf missing even_deny_root directive
          (root would be exempt from lockout)
      when: pam_hardening_faillock_even_deny_root

    - name: Assert faillock.conf audit directive present
      ansible.builtin.assert:
        that:
          - pam_hardening_verify_conf_text is search('(?m)^audit$')
        fail_msg: "faillock.conf missing audit directive"
      when: pam_hardening_faillock_audit

    - name: Assert faillock.conf dir setting
      ansible.builtin.assert:
        that:
          - "'dir = /run/faillock' in pam_hardening_verify_conf_text"
        fail_msg: "faillock.conf missing 'dir = /run/faillock'"

    - name: Assert faillock.conf Ansible managed header
      ansible.builtin.assert:
        that:
          - "'Ansible managed' in pam_hardening_verify_conf_text"
        fail_msg: "faillock.conf missing Ansible managed header"

    # ---- PAM stack: Arch / Void ----

    - name: Verify PAM stack on Arch/Void
      when: ansible_facts['os_family'] in ['Archlinux', 'Void']
      block:
        - name: Slurp /etc/pam.d/system-auth
          ansible.builtin.slurp:
            src: /etc/pam.d/system-auth
          register: pam_hardening_verify_system_auth_raw

        - name: Set system-auth text fact
          ansible.builtin.set_fact:
            pam_hardening_verify_system_auth_text: >-
              {{ pam_hardening_verify_system_auth_raw.content | b64decode }}

        - name: Assert pam_faillock.so preauth in system-auth
          ansible.builtin.assert:
            that:
              - >-
                pam_hardening_verify_system_auth_text is search(
                '(?m)^auth\s+required\s+pam_faillock\.so\s+preauth')
            fail_msg: >-
              /etc/pam.d/system-auth missing
              'auth required pam_faillock.so preauth' line

        - name: Assert pam_faillock.so authfail in system-auth
          ansible.builtin.assert:
            that:
              - >-
                pam_hardening_verify_system_auth_text is search(
                '(?m)^auth\s+required\s+pam_faillock\.so\s+authfail')
            fail_msg: >-
              /etc/pam.d/system-auth missing
              'auth required pam_faillock.so authfail' line

        - name: Assert pam_faillock.so account in system-auth
          ansible.builtin.assert:
            that:
              - >-
                pam_hardening_verify_system_auth_text is search(
                '(?m)^account\s+required\s+pam_faillock\.so')
            fail_msg: >-
              /etc/pam.d/system-auth missing
              'account required pam_faillock.so' line

    # ---- PAM stack: Debian / Ubuntu ----

    - name: Verify PAM stack on Debian/Ubuntu
      when: ansible_facts['os_family'] == 'Debian'
      block:
        - name: Stat pam-auth-update faillock profile
          ansible.builtin.stat:
            path: /usr/share/pam-configs/faillock
          register: pam_hardening_verify_deb_profile

        - name: Assert pam-auth-update faillock profile exists
          ansible.builtin.assert:
            that:
              - pam_hardening_verify_deb_profile.stat.exists
              - pam_hardening_verify_deb_profile.stat.isreg
            fail_msg: "/usr/share/pam-configs/faillock not deployed"

        - name: Stat pam-auth-update faillock-authfail profile
          ansible.builtin.stat:
            path: /usr/share/pam-configs/faillock-authfail
          register: pam_hardening_verify_deb_authfail_profile

        - name: Assert pam-auth-update faillock-authfail profile exists
          ansible.builtin.assert:
            that:
              - pam_hardening_verify_deb_authfail_profile.stat.exists
              - pam_hardening_verify_deb_authfail_profile.stat.isreg
            fail_msg: "/usr/share/pam-configs/faillock-authfail not deployed"

        - name: Slurp faillock pam-configs profile
          ansible.builtin.slurp:
            src: /usr/share/pam-configs/faillock
          register: pam_hardening_verify_deb_profile_raw

        - name: Assert faillock profile contains preauth
          ansible.builtin.assert:
            that:
              - >-
                (pam_hardening_verify_deb_profile_raw.content | b64decode)
                is search('pam_faillock\.so preauth')
            fail_msg: >-
              /usr/share/pam-configs/faillock missing
              pam_faillock.so preauth directive

    # ---- PAM stack: RedHat / Fedora ----

    - name: Verify PAM stack on RedHat/Fedora
      when: ansible_facts['os_family'] == 'RedHat'
      block:
        - name: Check authselect current profile
          ansible.builtin.command: authselect current
          register: pam_hardening_verify_authselect
          changed_when: false

        - name: Assert authselect has with-faillock feature
          ansible.builtin.assert:
            that:
              - "'with-faillock' in pam_hardening_verify_authselect.stdout"
            fail_msg: >-
              authselect does not have with-faillock feature enabled.
              Output: {{ pam_hardening_verify_authselect.stdout }}

    # ---- Diagnostic ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          pam_hardening verify passed on {{ ansible_facts['os_family'] }}:
          faillock.conf deployed (root:root 0644) with correct parameters,
          PAM stack configured for {{ ansible_facts['distribution'] }}.
```

### Design notes

- **`vars_files: ../../defaults/main.yml`** -- loads role defaults so assertions can reference `pam_hardening_faillock_deny` etc. dynamically. If the user overrides defaults, verify still passes as long as the rendered template matches.
- **`block` + `when`** -- groups platform-specific assertions cleanly; avoids `when:` on every individual task.
- **Regex assertions** use `(?m)` multiline flag for `^` anchoring on individual lines within slurped file content.
- **No vault dependency** -- the role uses no vault variables. Removed from all shared playbooks.
- **Variable naming** -- all register variables use `pam_hardening_verify_*` prefix per project convention.

---

## 8. Implementation Order

### Step 1: Create shared/ directory and move playbooks

1. Create `molecule/shared/` directory
2. Write `molecule/shared/converge.yml` (vault removed)
3. Write `molecule/shared/verify.yml` (expanded assertions per section 7)

### Step 2: Update default/ scenario

4. Rewrite `molecule/default/molecule.yml` to point playbooks at `../shared/`
5. Remove vault_password_file from config_options (not needed)
6. Add `idempotence` to test_sequence
7. Delete old `molecule/default/converge.yml` and `molecule/default/verify.yml`

### Step 3: Add docker/ scenario

8. Create `molecule/docker/` directory
9. Write `molecule/docker/molecule.yml` per section 4
10. Write `molecule/docker/prepare.yml` (pacman cache update)

### Step 4: Run and validate docker scenario

11. Run `molecule test -s docker` from the role directory
12. Verify all assertions pass on Arch container
13. Verify idempotence passes (lineinfile tasks should not report changed on second run)
14. Fix any issues discovered

### Step 5: Add vagrant/ scenario

15. Create `molecule/vagrant/` directory
16. Write `molecule/vagrant/molecule.yml` per section 5
17. Write `molecule/vagrant/prepare.yml` (keyring refresh + apt cache)

### Step 6: Run and validate vagrant scenario

18. Run `molecule test -s vagrant` from the role directory
19. Verify Arch VM: faillock.conf + system-auth assertions pass
20. Verify Ubuntu VM: faillock.conf + pam-configs assertions pass
21. Verify idempotence passes on both platforms
22. Fix any issues discovered (expect Arch keyring / Ubuntu apt issues first run)

### Step 7: Run default scenario with updated shared playbooks

23. Run `molecule test -s default` (localhost)
24. Verify backward compatibility with the existing local test workflow

### Step 8: Clean up

25. Remove any remaining references to vault in pam_hardening molecule files
26. Verify no orphaned files in molecule/default/ (old converge.yml, verify.yml)

---

## 9. Risks / Notes

### PAM testing limitations in containers

- **Cannot test actual login lockout.** Docker containers do not run login/sshd by default. Even with systemd, there is no user session to authenticate against. Tests are limited to verifying file content.
- **`pam-auth-update --package` requires debconf.** On a minimal Debian container the `libpam-runtime` package must be installed. The Arch systemd container does not have Debian tools, so Debian tests are Vagrant-only.
- **lineinfile idempotence.** The `lineinfile` module with `insertbefore`/`insertafter` should be idempotent as long as the `line:` parameter matches exactly. If the spacing in `/etc/pam.d/system-auth` differs between Arch releases, the regex in verify.yml (`\s+`) handles varying whitespace.

### Arch container specifics

- The `ghcr.io/textyre/bootstrap/arch-systemd:latest` image includes the `pam` package (provides `/etc/pam.d/system-auth` and the `pam_faillock.so` module). If the base image changes, `prepare.yml` may need to install `pam` explicitly.
- `pacman -Sy` in prepare is required because the container's package cache may be stale (same pattern as ntp, hostname, locale docker scenarios).

### Vagrant specifics

- **generic/arch box stale keyring** -- the prepare.yml includes the established keyring refresh workaround (temporarily set `SigLevel = Never`, install archlinux-keyring, restore, repopulate). This is copied from the `package_manager` vagrant scenario which has been validated.
- **Ubuntu 24.04 (bento/ubuntu-24.04)** -- `libpam-modules` package includes `pam_faillock.so` since Ubuntu 22.04+. No extra package installation needed. The `pam-auth-update` tool is part of `libpam-runtime` which is installed by default.
- **Vagrant/libvirt provider** -- requires `vagrant-libvirt` plugin and KVM on the CI host. See `2026-02-24-package-manager-vagrant-design.md` for CI environment setup notes.

### authselect (Fedora) testing gap

- Neither the Docker scenario (Arch-only image) nor the Vagrant scenario (Arch + Ubuntu) tests the Fedora/RedHat path. The verify.yml includes Fedora assertions guarded by `when: ansible_facts['os_family'] == 'RedHat'`, so they will be silently skipped.
- **Future:** Add a `bento/fedora-41` platform to the vagrant scenario if Fedora support becomes a testing priority.

### faillock_enabled toggle

- The converge playbook applies the role with defaults (`pam_hardening_faillock_enabled: true`). There is no negative test (disabled toggle). A future enhancement could add a second converge pass with `pam_hardening_faillock_enabled: false` and verify that faillock lines are removed from system-auth. This is out of scope for the initial implementation.

### File structure after implementation

```
ansible/roles/pam_hardening/
  molecule/
    shared/
      converge.yml              # no vault, applies pam_hardening role
      verify.yml                # expanded: 20+ assertions across all platforms
    default/
      molecule.yml              # localhost, points to ../shared/*
    docker/
      molecule.yml              # Arch systemd container
      prepare.yml               # pacman -Sy
    vagrant/
      molecule.yml              # generic/arch + bento/ubuntu-24.04
      prepare.yml               # keyring refresh + apt cache
```
