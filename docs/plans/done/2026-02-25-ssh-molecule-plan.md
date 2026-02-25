# Plan: SSH Role -- Molecule Testing & Bug Fixes

**Date:** 2026-02-25
**Status:** Draft
**Role:** `ansible/roles/ssh/`

---

## 1. Current State

### What the Role Does

The `ssh` role provides full sshd hardening aligned with dev-sec.io, CIS Benchmark, and Mozilla Modern guidelines. It covers:

- **Installation**: OS-specific packages via `install-{os_family}.yml` and vars files per OS family
- **Preflight lockout protection**: Verifies the target user is in AllowGroups/AllowUsers before deploying config
- **Hardening**: Deploys `sshd_config.j2` template with cryptography, authentication, access control, forwarding, logging, and DoS settings; cleans up weak host keys (DSA/ECDSA); generates ed25519/RSA keys
- **DH moduli cleanup**: Optional removal of weak Diffie-Hellman parameters
- **Banner**: Optional pre-auth legal banner via `issue.net.j2`
- **Service management**: Init-system-agnostic enable/start via `ssh_service_name` map
- **In-role verification**: `sshd -t` config check and `pgrep sshd` liveness check
- **Reporting**: Phase reports via `common` role

### OS Support

| OS Family | Package(s) | Service Name (systemd) |
|-----------|-----------|----------------------|
| Archlinux | `openssh` | `sshd` |
| Debian | `openssh-server`, `openssh-client` | `ssh` |
| RedHat | `openssh-server`, `openssh-clients` | `sshd` |
| Void | `openssh` | `sshd` |
| Gentoo | `net-misc/openssh` | `sshd` |

### Existing Molecule Tests

Single scenario at `molecule/default/`:

- **Driver**: `default` (localhost, managed: false)
- **Provisioner**: Uses vault password file, ANSIBLE_ROLES_PATH set to `roles/` (not `../` -- non-standard)
- **converge.yml**: Applies `ssh` role with `ssh_banner_enabled: true` and `ssh_moduli_cleanup: true`; loads vault.yml
- **verify.yml**: 17 assertion tasks covering:
  - sshd_config exists with 0600/root permissions
  - 6 security directives (PermitRootLogin, PasswordAuthentication, PermitEmptyPasswords, HostbasedAuthentication, PermitUserEnvironment, StrictModes)
  - 3 forwarding directives (X11, TCP, Agent)
  - LogLevel VERBOSE
  - Cipher/MAC/KEX negative checks (reject weak algorithms)
  - Host key assertions (no DSA, ed25519 exists)
  - UseDNS no, Compression no
  - Banner file exists
  - `sshd -t` validation
- **test_sequence**: syntax, converge, verify (no idempotence)

### Key Variables

- `ssh_user`: Defined in inventory (`system.yml` line 62: `"{{ target_user }}"`), NOT in role defaults -- molecule must supply it
- `_ssh_supported_os`: Referenced in `tasks/main.yml` line 8 as `_ssh_supported_os` (underscore prefix) but defaults defines `ssh_supported_os` (no underscore) -- **this is a latent bug** (the underscore-prefixed version is never defined; the assertion passes only because `ansible_facts['os_family'] in _ssh_supported_os` evaluates to `false` when `_ssh_supported_os` is undefined, causing the `assert` to fail, but evidently this is masked in current testing)

---

## 2. Bug Fix Plans

### BUG-01: Variable Name Mismatch `_ssh_supported_os` vs `ssh_supported_os`

**File:** `tasks/main.yml` line 8

**Problem:** The assertion references `_ssh_supported_os` but defaults/main.yml defines `ssh_supported_os`. The underscore-prefixed variable is never set. This either always fails (blocking the role) or is somehow masked. Likely the code was meant to use `ssh_supported_os`.

**Fix:**

```yaml
# tasks/main.yml line 8 -- change:
      - ansible_facts['os_family'] in _ssh_supported_os
# to:
      - ansible_facts['os_family'] in ssh_supported_os
```

### BUG-02: Preflight Variable Name Mismatch `_ssh_user_groups` vs `ssh_user_groups`

**File:** `tasks/preflight.yml` lines 25 and 50

**Problem:** The `id -nG` command registers into `ssh_user_groups` (line 10), but the `when:` conditions reference `_ssh_user_groups.stdout.split()` (underscore prefix). Same class of bug as BUG-01.

**Fix:**

```yaml
# preflight.yml line 25 -- change:
    - ssh_allow_groups | intersect(_ssh_user_groups.stdout.split()) | length == 0
# to:
    - ssh_allow_groups | intersect(ssh_user_groups.stdout.split()) | length == 0

# preflight.yml line 50 -- change:
    - ssh_deny_groups | intersect(_ssh_user_groups.stdout.split()) | length > 0
# to:
    - ssh_deny_groups | intersect(ssh_user_groups.stdout.split()) | length > 0
```

### BUG-03: Moduli Variable Name Mismatches

**File:** `tasks/moduli.yml` lines 31, 44, 45

**Problem:** Registered variables are `ssh_weak_moduli` and `ssh_strong_moduli` but `when:` conditions reference `_ssh_weak_moduli` and `_ssh_strong_moduli`.

**Fix:**

```yaml
# moduli.yml line 31 -- change _ssh_weak_moduli to ssh_weak_moduli
# moduli.yml line 44 -- change _ssh_weak_moduli to ssh_weak_moduli
# moduli.yml line 45 -- change _ssh_strong_moduli to ssh_strong_moduli
```

### CRIT-05: `ssh_user` Not Defined in Role Defaults

**File:** `tasks/preflight.yml` uses `ssh_user` which comes from inventory `system.yml`

**Problem:** When running molecule in docker/vagrant (no inventory loaded), `ssh_user` is undefined. The role should either:
1. Define `ssh_user` in `defaults/main.yml` with a sensible default, or
2. The converge.yml must explicitly set it as a role var

**Fix:** Add to `defaults/main.yml`:

```yaml
# Пользователь для проверки lockout-защиты (по умолчанию текущий пользователь)
ssh_user: "{{ ansible_user_id }}"
```

### MED-03: SSH Handler Lacks `listen:` Directive

**File:** `handlers/main.yml`

**Problem:** No `listen:` directive on either handler. Other roles cannot cross-notify sshd restarts without tight coupling.

**Fix:**

```yaml
---
# === SSH handlers (init-system agnostic) ===

- name: "Restart sshd"
  ansible.builtin.service:
    name: "{{ ssh_service_name[ansible_facts['service_mgr']] | default('sshd') }}"
    state: restarted
  listen: "restart sshd"

- name: "Reload sshd"
  ansible.builtin.service:
    name: "{{ ssh_service_name[ansible_facts['service_mgr']] | default('sshd') }}"
    state: reloaded
  listen: "reload sshd"
```

---

## 3. Shared Migration

Move existing `molecule/default/converge.yml` and `molecule/default/verify.yml` into `molecule/shared/` so all scenarios reuse them.

### New Directory Layout

```
ansible/roles/ssh/molecule/
  shared/
    converge.yml      <-- moved+adapted from default/converge.yml
    verify.yml        <-- moved+rewritten from default/verify.yml
  default/
    molecule.yml      <-- updated to point at ../shared/
  docker/
    molecule.yml      <-- new (Arch systemd container)
    prepare.yml       <-- new (pacman -Sy)
  vagrant/
    molecule.yml      <-- new (Arch + Ubuntu VMs)
    prepare.yml       <-- new (cross-platform package cache update)
```

### shared/converge.yml

Adapted from the existing converge.yml. Key changes:
- Remove `vars_files` vault dependency (not needed for molecule docker/vagrant)
- Add `ssh_user` var explicitly
- Keep feature flags (`ssh_banner_enabled`, `ssh_moduli_cleanup`)
- Skip `report` tag (common role not available in isolated molecule)

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: ssh
      vars:
        ssh_user: root
        ssh_banner_enabled: true
        ssh_moduli_cleanup: true
        ssh_allow_groups: []
```

**Note on `ssh_allow_groups: []`**: In docker containers the `wheel` group may not exist and root is not a member. Setting to empty list skips AllowGroups entirely, avoiding lockout failures in the test environment. Vagrant scenarios that create a real user can override this.

### default/molecule.yml (Updated)

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
  options:
    skip-tags: report
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

Changes from current:
- `ANSIBLE_ROLES_PATH` changed from `roles/` to `../` (standard pattern per NTP reference)
- Playbooks now at `../shared/`
- Added `idempotence` to test_sequence
- Added `skip-tags: report`

---

## 4. Docker Scenario

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

### molecule/docker/prepare.yml

sshd in a container needs host keys and the privilege separation directory. The arch-systemd image has openssh pre-installed but may not have generated host keys.

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

    - name: Ensure privilege separation directory exists
      ansible.builtin.file:
        path: /run/sshd
        state: directory
        mode: "0755"
```

### Docker-Specific Considerations

1. **sshd requires host keys**: The `harden.yml` task generates ed25519 and RSA keys via `ssh-keygen` with `creates:` guard, so this is handled by the role itself.
2. **Privilege separation directory**: sshd 9.x requires `/run/sshd` to exist. In a systemd container with `tmpfs: [/run]`, this directory is wiped on container start. The prepare step ensures it exists. The role's `service.yml` starts sshd which also expects this.
3. **`sshd -t` validation**: Works in containers; it validates config syntax without needing a running daemon.
4. **`pgrep sshd` in verify.yml**: After the role enables+starts sshd via systemd, it should be running. The container must have systemd as PID 1 for this to work (hence the `command: /usr/lib/systemd/systemd` platform config).
5. **No `wheel` group in container**: The converge.yml sets `ssh_allow_groups: []` to avoid AllowGroups failures.
6. **`report` tag skipped**: The `common` role is not present in isolated molecule runs. Skipping the `report` tag prevents failures on `include_role: common`.

---

## 5. Vagrant Scenario

### molecule/vagrant/molecule.yml

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: archlinux/archlinux
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: generic/ubuntu2404
    memory: 2048
    cpus: 2

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

### molecule/vagrant/prepare.yml

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_os_family == 'Archlinux'

    - name: Update apt package cache (Debian/Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_os_family == 'Debian'

    - name: Ensure privilege separation directory exists
      ansible.builtin.file:
        path: /run/sshd
        state: directory
        mode: "0755"
```

### Cross-Platform Differences

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|-------------|
| Package | `openssh` | `openssh-server`, `openssh-client` |
| Service name (systemd) | `sshd` | `ssh` |
| Config path | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` |
| sshd binary path | `/usr/sbin/sshd` | `/usr/sbin/sshd` |
| Privilege sep dir | `/run/sshd` (may need creation) | `/run/sshd` (created by package) |
| Default host keys | Generated by `openssh` post-install | Generated by `openssh-server` post-install |
| ChallengeResponseAuthentication | Supported | Deprecated in OpenSSH 9.x; alias for `KbdInteractiveAuthentication` |
| DH moduli | `/etc/ssh/moduli` | `/etc/ssh/moduli` |
| Banner path default | `/etc/issue.net` | `/etc/issue.net` (exists by default on Ubuntu) |

**Important:** On Ubuntu 24.04, `ChallengeResponseAuthentication` in sshd_config emits a deprecation warning but is still accepted as an alias. The `sshd -t` validation will succeed but may log a warning. This does not block deployment.

---

## 6. Verify.yml Design

The shared `verify.yml` must work on both Arch and Ubuntu. It uses `ansible_os_family` guards where behavior differs.

### shared/verify.yml

```yaml
---
- name: Verify SSH role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ================================================================
    #  Package installation
    # ================================================================

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    - name: Assert openssh package installed (Arch)
      ansible.builtin.assert:
        that: "'openssh' in ansible_facts.packages"
        fail_msg: "openssh package not found on Archlinux"
      when: ansible_os_family == 'Archlinux'

    - name: Assert openssh-server package installed (Debian)
      ansible.builtin.assert:
        that: "'openssh-server' in ansible_facts.packages"
        fail_msg: "openssh-server package not found on Debian/Ubuntu"
      when: ansible_os_family == 'Debian'

    # ================================================================
    #  Service running and enabled
    # ================================================================

    - name: Gather service facts
      ansible.builtin.service_facts:

    - name: Assert sshd.service is running and enabled (Arch/RedHat)
      ansible.builtin.assert:
        that:
          - "'sshd.service' in ansible_facts.services"
          - "ansible_facts.services['sshd.service'].state == 'running'"
          - "ansible_facts.services['sshd.service'].status == 'enabled'"
        fail_msg: "sshd.service is not running or not enabled"
      when: ansible_os_family in ['Archlinux', 'RedHat']

    - name: Assert ssh.service is running and enabled (Debian)
      ansible.builtin.assert:
        that:
          - "'ssh.service' in ansible_facts.services"
          - "ansible_facts.services['ssh.service'].state == 'running'"
          - "ansible_facts.services['ssh.service'].status == 'enabled'"
        fail_msg: "ssh.service is not running or not enabled"
      when: ansible_os_family == 'Debian'

    # ================================================================
    #  sshd_config file permissions
    # ================================================================

    - name: Stat /etc/ssh/sshd_config
      ansible.builtin.stat:
        path: /etc/ssh/sshd_config
      register: ssh_verify_config

    - name: Assert sshd_config exists with correct permissions
      ansible.builtin.assert:
        that:
          - ssh_verify_config.stat.exists
          - ssh_verify_config.stat.mode == '0600'
          - ssh_verify_config.stat.pw_name == 'root'
        fail_msg: >-
          /etc/ssh/sshd_config missing or wrong permissions
          (expected root:root 0600, got {{ ssh_verify_config.stat.pw_name }}:
          {{ ssh_verify_config.stat.mode | default('missing') }})

    # ================================================================
    #  sshd_config content -- slurp and check directives
    # ================================================================

    - name: Read sshd_config
      ansible.builtin.slurp:
        src: /etc/ssh/sshd_config
      register: ssh_verify_config_raw

    - name: Set sshd_config text fact
      ansible.builtin.set_fact:
        ssh_verify_config_text: "{{ ssh_verify_config_raw.content | b64decode }}"

    # ---- Critical security directives ----

    - name: Assert PermitRootLogin no
      ansible.builtin.assert:
        that: "'PermitRootLogin no' in ssh_verify_config_text"
        fail_msg: "PermitRootLogin is not set to 'no'"

    - name: Assert PasswordAuthentication no
      ansible.builtin.assert:
        that: "'PasswordAuthentication no' in ssh_verify_config_text"
        fail_msg: "PasswordAuthentication is not set to 'no'"

    - name: Assert PermitEmptyPasswords no
      ansible.builtin.assert:
        that: "'PermitEmptyPasswords no' in ssh_verify_config_text"
        fail_msg: "PermitEmptyPasswords is not set to 'no'"

    - name: Assert HostbasedAuthentication no
      ansible.builtin.assert:
        that: "'HostbasedAuthentication no' in ssh_verify_config_text"
        fail_msg: "HostbasedAuthentication is not set to 'no'"

    - name: Assert PermitUserEnvironment no
      ansible.builtin.assert:
        that: "'PermitUserEnvironment no' in ssh_verify_config_text"
        fail_msg: "PermitUserEnvironment is not set to 'no'"

    - name: Assert StrictModes yes
      ansible.builtin.assert:
        that: "'StrictModes yes' in ssh_verify_config_text"
        fail_msg: "StrictModes is not set to 'yes'"

    # ---- Authentication methods ----

    - name: Assert AuthenticationMethods publickey
      ansible.builtin.assert:
        that: "'AuthenticationMethods publickey' in ssh_verify_config_text"
        fail_msg: "AuthenticationMethods not set to 'publickey'"

    - name: Assert PubkeyAuthentication yes
      ansible.builtin.assert:
        that: "'PubkeyAuthentication yes' in ssh_verify_config_text"
        fail_msg: "PubkeyAuthentication is not set to 'yes'"

    - name: Assert UsePAM yes
      ansible.builtin.assert:
        that: "'UsePAM yes' in ssh_verify_config_text"
        fail_msg: "UsePAM is not set to 'yes'"

    # ---- Forwarding and tunnels ----

    - name: Assert X11Forwarding no
      ansible.builtin.assert:
        that: "'X11Forwarding no' in ssh_verify_config_text"
        fail_msg: "X11Forwarding is not set to 'no'"

    - name: Assert AllowTcpForwarding no
      ansible.builtin.assert:
        that: "'AllowTcpForwarding no' in ssh_verify_config_text"
        fail_msg: "AllowTcpForwarding is not set to 'no'"

    - name: Assert AllowAgentForwarding no
      ansible.builtin.assert:
        that: "'AllowAgentForwarding no' in ssh_verify_config_text"
        fail_msg: "AllowAgentForwarding is not set to 'no'"

    - name: Assert PermitTunnel no
      ansible.builtin.assert:
        that: "'PermitTunnel no' in ssh_verify_config_text"
        fail_msg: "PermitTunnel is not set to 'no'"

    - name: Assert GatewayPorts no
      ansible.builtin.assert:
        that: "'GatewayPorts no' in ssh_verify_config_text"
        fail_msg: "GatewayPorts is not set to 'no'"

    # ---- Logging ----

    - name: Assert LogLevel VERBOSE
      ansible.builtin.assert:
        that: "'LogLevel VERBOSE' in ssh_verify_config_text"
        fail_msg: "LogLevel is not set to 'VERBOSE'"

    - name: Assert SyslogFacility AUTH
      ansible.builtin.assert:
        that: "'SyslogFacility AUTH' in ssh_verify_config_text"
        fail_msg: "SyslogFacility is not set to 'AUTH'"

    # ---- Network ----

    - name: Assert UseDNS no
      ansible.builtin.assert:
        that: "'UseDNS no' in ssh_verify_config_text"
        fail_msg: "UseDNS is not set to 'no'"

    - name: Assert Compression no
      ansible.builtin.assert:
        that: "'Compression no' in ssh_verify_config_text"
        fail_msg: "Compression is not set to 'no'"

    # ---- Session ----

    - name: Assert MaxAuthTries 3
      ansible.builtin.assert:
        that: "'MaxAuthTries 3' in ssh_verify_config_text"
        fail_msg: "MaxAuthTries is not set to 3"

    - name: Assert MaxStartups 10:30:60
      ansible.builtin.assert:
        that: "'MaxStartups 10:30:60' in ssh_verify_config_text"
        fail_msg: "MaxStartups is not set to '10:30:60'"

    - name: Assert LoginGraceTime 60
      ansible.builtin.assert:
        that: "'LoginGraceTime 60' in ssh_verify_config_text"
        fail_msg: "LoginGraceTime is not set to 60"

    # ---- Cryptography -- negative checks ----

    - name: Assert no weak ciphers
      ansible.builtin.assert:
        that:
          - "'cbc' not in ssh_verify_config_text | regex_search('Ciphers .*')"
          - "'arcfour' not in ssh_verify_config_text | regex_search('Ciphers .*')"
          - "'3des' not in ssh_verify_config_text | regex_search('Ciphers .*')"
        fail_msg: "Weak ciphers detected in Ciphers line"

    - name: Assert no weak MACs
      ansible.builtin.assert:
        that:
          - "'md5' not in ssh_verify_config_text | regex_search('MACs .*')"
          - "'umac-64' not in ssh_verify_config_text | regex_search('MACs .*')"
        fail_msg: "Weak MACs detected in MACs line"

    - name: Assert no weak KEX
      ansible.builtin.assert:
        that:
          - "'group1' not in ssh_verify_config_text | regex_search('KexAlgorithms .*')"
        fail_msg: "Weak KEX algorithm detected in KexAlgorithms line"

    # ---- Cryptography -- positive checks ----

    - name: Assert chacha20-poly1305 in ciphers
      ansible.builtin.assert:
        that: "'chacha20-poly1305@openssh.com' in ssh_verify_config_text"
        fail_msg: "chacha20-poly1305 not in Ciphers"

    - name: Assert curve25519-sha256 in KEX
      ansible.builtin.assert:
        that: "'curve25519-sha256' in ssh_verify_config_text"
        fail_msg: "curve25519-sha256 not in KexAlgorithms"

    - name: Assert ssh-ed25519 in HostKeyAlgorithms
      ansible.builtin.assert:
        that: "'ssh-ed25519' in ssh_verify_config_text"
        fail_msg: "ssh-ed25519 not in HostKeyAlgorithms"

    - name: Assert RekeyLimit configured
      ansible.builtin.assert:
        that: "'RekeyLimit' in ssh_verify_config_text"
        fail_msg: "RekeyLimit directive missing"

    # ================================================================
    #  Host keys
    # ================================================================

    - name: Stat ed25519 host key
      ansible.builtin.stat:
        path: /etc/ssh/ssh_host_ed25519_key
      register: ssh_verify_ed25519_key

    - name: Assert ed25519 host key exists
      ansible.builtin.assert:
        that: ssh_verify_ed25519_key.stat.exists
        fail_msg: "/etc/ssh/ssh_host_ed25519_key not found"

    - name: Stat DSA host key
      ansible.builtin.stat:
        path: /etc/ssh/ssh_host_dsa_key
      register: ssh_verify_dsa_key

    - name: Assert no DSA host key
      ansible.builtin.assert:
        that: not ssh_verify_dsa_key.stat.exists
        fail_msg: "Weak DSA host key still present at /etc/ssh/ssh_host_dsa_key"

    - name: Stat ECDSA host key
      ansible.builtin.stat:
        path: /etc/ssh/ssh_host_ecdsa_key
      register: ssh_verify_ecdsa_key

    - name: Assert no ECDSA host key
      ansible.builtin.assert:
        that: not ssh_verify_ecdsa_key.stat.exists
        fail_msg: "Weak ECDSA host key still present at /etc/ssh/ssh_host_ecdsa_key"

    # ================================================================
    #  Banner
    # ================================================================

    - name: Stat banner file
      ansible.builtin.stat:
        path: /etc/issue.net
      register: ssh_verify_banner

    - name: Assert banner file exists
      ansible.builtin.assert:
        that: ssh_verify_banner.stat.exists
        fail_msg: "/etc/issue.net not found (ssh_banner_enabled was true in converge)"

    - name: Assert Banner directive in sshd_config
      ansible.builtin.assert:
        that: "'Banner /etc/issue.net' in ssh_verify_config_text"
        fail_msg: "Banner directive not found in sshd_config"

    # ================================================================
    #  SFTP subsystem
    # ================================================================

    - name: Assert SFTP subsystem configured
      ansible.builtin.assert:
        that: "'Subsystem sftp internal-sftp' in ssh_verify_config_text"
        fail_msg: "SFTP subsystem not configured (expected 'Subsystem sftp internal-sftp')"

    # ================================================================
    #  Config syntax validation
    # ================================================================

    - name: Validate sshd configuration (sshd -t)
      ansible.builtin.command:
        cmd: sshd -t
      changed_when: false
      register: ssh_verify_sshd_t
      failed_when: ssh_verify_sshd_t.rc != 0

    # ================================================================
    #  Managed header
    # ================================================================

    - name: Assert Ansible managed comment present
      ansible.builtin.assert:
        that: "'Ansible managed' in ssh_verify_config_text"
        fail_msg: "Ansible managed comment not found in sshd_config"

    # ================================================================
    #  Diagnostic
    # ================================================================

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          SSH verify passed: packages installed, service running+enabled,
          sshd_config correct (0600 root, all security directives verified),
          host keys correct (ed25519 present, DSA/ECDSA absent),
          cryptography validated, banner deployed, sshd -t passed.
```

### Assertion Inventory (38 total)

| Category | Count | Details |
|----------|-------|---------|
| Package installation | 2 | Arch: `openssh`; Debian: `openssh-server` (guarded by `ansible_os_family`) |
| Service state | 2 | Arch: `sshd.service`; Debian: `ssh.service` (guarded) |
| Config permissions | 1 | 0600/root |
| Security directives | 6 | PermitRootLogin, PasswordAuth, EmptyPasswords, Hostbased, UserEnv, StrictModes |
| Auth methods | 3 | AuthenticationMethods, PubkeyAuth, UsePAM |
| Forwarding/tunnels | 5 | X11, TCP, Agent, Tunnel, GatewayPorts |
| Logging | 2 | LogLevel, SyslogFacility |
| Network | 2 | UseDNS, Compression |
| Session/DoS | 3 | MaxAuthTries, MaxStartups, LoginGraceTime |
| Crypto negative | 3 | No weak ciphers, MACs, KEX |
| Crypto positive | 4 | chacha20, curve25519, ed25519, RekeyLimit |
| Host keys | 3 | ed25519 exists, no DSA, no ECDSA |
| Banner | 2 | File exists, directive in config |
| SFTP | 1 | Subsystem configured |
| Syntax validation | 1 | `sshd -t` |
| Managed header | 1 | Ansible managed comment |
| Diagnostic | 1 | Summary debug output |

---

## 7. Implementation Order

### Phase 1: Bug Fixes (prerequisites for all testing)

1. Fix `_ssh_supported_os` -> `ssh_supported_os` in `tasks/main.yml` line 8
2. Fix `_ssh_user_groups` -> `ssh_user_groups` in `tasks/preflight.yml` lines 25, 50
3. Fix `_ssh_weak_moduli` / `_ssh_strong_moduli` -> `ssh_weak_moduli` / `ssh_strong_moduli` in `tasks/moduli.yml` lines 31, 44, 45
4. Add `ssh_user: "{{ ansible_user_id }}"` to `defaults/main.yml`
5. Add `listen:` directives to `handlers/main.yml`

### Phase 2: Shared Migration

6. Create `molecule/shared/` directory
7. Write `molecule/shared/converge.yml` (see section 3)
8. Write `molecule/shared/verify.yml` (see section 6)
9. Update `molecule/default/molecule.yml` to point at `../shared/` playbooks and fix `ANSIBLE_ROLES_PATH`
10. Delete old `molecule/default/converge.yml` and `molecule/default/verify.yml`
11. Run `molecule test -s default` to validate shared migration

### Phase 3: Docker Scenario

12. Create `molecule/docker/molecule.yml` (see section 4)
13. Create `molecule/docker/prepare.yml` (see section 4)
14. Run `molecule test -s docker` and fix any failures

### Phase 4: Vagrant Scenario

15. Create `molecule/vagrant/molecule.yml` (see section 5)
16. Create `molecule/vagrant/prepare.yml` (see section 5)
17. Run `molecule test -s vagrant` on a KVM-capable host and fix cross-platform failures

### Phase 5: CI Integration

18. Add docker scenario to existing `molecule-docker.yml` GitHub Actions workflow (or create one)
19. Add vagrant scenario to `molecule-vagrant.yml` workflow with matrix `[arch-vm, ubuntu-noble]`

---

## 8. Risks / Notes

### SSH in Docker Containers

1. **Host key generation**: sshd refuses to start without host keys. The role's `harden.yml` generates them via `ssh-keygen` with `creates:` guard. This works in containers but requires `ssh-keygen` to be installed (it comes with the `openssh` package).

2. **Privilege separation directory**: OpenSSH 9.x requires `/run/sshd` for privilege separation. In systemd containers with `tmpfs: [/run]`, this directory does not persist across restarts. The `prepare.yml` creates it before converge. The role does not create this directory itself (assumes the package post-install script does).

3. **`pgrep sshd` unreliability**: The in-role `tasks/verify.yml` uses `pgrep sshd` which may match the config-validation `sshd -t` process or fail if sshd is started but exits quickly. The molecule verify.yml uses `service_facts` instead, which is more reliable.

4. **ChallengeResponseAuthentication deprecation**: OpenSSH >= 8.7 deprecated this in favor of `KbdInteractiveAuthentication`. The `sshd -t` check may log a warning on Ubuntu 24.04 (OpenSSH 9.x) but still returns rc=0. This is a non-blocking cosmetic issue. A future enhancement could conditionally use `KbdInteractiveAuthentication` on newer OpenSSH.

### SSH in Vagrant VMs

5. **Vagrant uses SSH for provisioning**: Vagrant itself connects to VMs via SSH. The role hardens sshd with `PasswordAuthentication no` and `AllowGroups []`. If AllowGroups were set to `wheel`, the `vagrant` user (which Vagrant uses for provisioning) would be locked out mid-converge. The converge.yml sets `ssh_allow_groups: []` to prevent this. An alternative is adding the vagrant user to wheel in `prepare.yml`.

6. **Idempotence and host key generation**: The `ssh-keygen` tasks use `creates:` and will not re-run. Host key cleanup (DSA/ECDSA removal) is idempotent via `state: absent`. The `sshd_config` template deployment is idempotent (no change on second run). Moduli cleanup is conditionally idempotent (no-op if weak moduli already removed).

7. **Ubuntu `ssh` vs `sshd` service name**: On Debian/Ubuntu, the systemd service is `ssh.service`, not `sshd.service`. The role handles this via `vars/debian.yml` setting `ssh_service_name.systemd: ssh`. The verify.yml checks both variants with `when:` guards.

### Variable Dependencies

8. **`ssh_user` from inventory**: The `ssh_user` variable comes from `inventory/group_vars/all/system.yml` as `"{{ target_user }}"`. In molecule, this is not available. Adding `ssh_user: "{{ ansible_user_id }}"` to `defaults/main.yml` provides a fallback. The converge.yml can also set it explicitly as `root`.

9. **`common` role dependency**: The role includes `common` role for reporting. In molecule, the `common` role must either be available (via `ANSIBLE_ROLES_PATH`) or skipped via `skip-tags: report`. The latter approach is used, matching the NTP docker scenario pattern.

### Underscore-Prefixed Variable Convention

10. **Bug pattern across role**: Three files (`main.yml`, `preflight.yml`, `moduli.yml`) reference variables with `_ssh_` prefix that are registered without the prefix. This suggests a naming convention misunderstanding (perhaps intended as "private" variables using underscore prefix, but register statements omit it). All three must be fixed before molecule tests can pass.
