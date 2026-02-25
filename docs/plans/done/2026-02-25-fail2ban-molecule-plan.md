# Plan: fail2ban role -- Molecule testing (shared + Docker + Vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/fail2ban/`

---

## 1. Current State

### What the role does

The `fail2ban` role deploys brute-force protection for SSH:

- Validates the OS family against `_fail2ban_supported_os` (see Bug BUG-01 below)
- Includes OS-specific variables from `vars/<os_family>.yml` (package names, service names)
- Installs fail2ban via `ansible.builtin.package` (`tasks/install.yml`)
- Deploys `/etc/fail2ban/jail.d/sshd.conf` from `jail_sshd.conf.j2` template (`tasks/configure.yml`)
- Enables and starts the fail2ban service (`ansible.builtin.service`)
- Runs built-in verification via `fail2ban-client status` and `fail2ban-client status sshd` (`tasks/verify.yml`)
- Reports execution via `common` role's `report_phase.yml` / `report_render.yml` (tagged `report`)

**Template** (`jail_sshd.conf.j2`) produces:

```ini
[sshd]
enabled = true
port = 22
maxretry = 5
findtime = 600
bantime = 3600
bantime.increment = true
bantime.maxtime = 86400
backend = auto
ignoreip = 127.0.0.1/8 ::1
```

**Variables** (`defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `fail2ban_enabled` | `true` | Master toggle |
| `fail2ban_sshd_enabled` | `true` | Enable SSH jail |
| `fail2ban_sshd_port` | `{{ ssh_port \| default(22) }}` | Port to monitor |
| `fail2ban_sshd_maxretry` | `5` | Failed attempts before ban |
| `fail2ban_sshd_findtime` | `600` | Failure counting window (seconds) |
| `fail2ban_sshd_bantime` | `3600` | Initial ban duration (seconds) |
| `fail2ban_sshd_bantime_increment` | `true` | Progressive ban escalation |
| `fail2ban_sshd_bantime_maxtime` | `86400` | Maximum ban duration (seconds) |
| `fail2ban_sshd_backend` | `auto` | Log backend (auto/systemd/pyinotify/polling) |
| `fail2ban_ignoreip` | `[127.0.0.1/8, ::1]` | Whitelist |

**OS-specific vars** (all in `vars/`):

| OS family | Package | Service name (all init systems) |
|-----------|---------|--------------------------------|
| Archlinux | `fail2ban` | `fail2ban` |
| Debian | `fail2ban` | `fail2ban` |
| RedHat | `fail2ban` | `fail2ban` |
| Void | `fail2ban` | `fail2ban` |
| Gentoo | `net-analyzer/fail2ban` | `fail2ban` |

**Handler:** `Restart fail2ban` with `listen: "restart fail2ban"` -- follows project convention.

**Dependencies:** None declared in `meta/main.yml`. Runtime dependency on `common` role for report tasks (skipped in molecule via `skip-tags: report`).

### What tests exist now

Single `molecule/default/` scenario:

- **Driver:** `default` (localhost, `managed: false`)
- **Provisioner:** Ansible with vault password file, local connection
- **converge.yml:** Asserts `os_family == Archlinux`, applies `fail2ban` role with `maxretry: 3`, `bantime: 600`
- **verify.yml:** 6 checks:
  1. `fail2ban-client --version` returns rc 0
  2. `/etc/fail2ban/jail.d/sshd.conf` exists with mode `0644`
  3. Config contains `maxretry = 3`
  4. Config contains `bantime = 600`
  5. `service_facts` shows `fail2ban.service` running (systemd only)
  6. Debug summary message
- **test_sequence:** syntax, converge, verify (no idempotence, no destroy)

### Gaps in current tests

- **Cross-platform:** converge.yml hard-asserts `os_family == Archlinux` -- cannot test Ubuntu/Debian
- **No idempotence check** in test sequence
- **No package_facts** assertion (uses `fail2ban-client --version` command instead)
- **No service enabled check** -- only checks running state
- **No template content verification** beyond maxretry/bantime (missing: findtime, backend, ignoreip, bantime.increment, bantime.maxtime)
- **No Ansible managed marker** check
- **No config owner/group** check (only mode)
- **Vault dependency** in molecule.yml is unnecessary -- role has no vault variables
- **No Docker or Vagrant scenarios**
- **Hardcoded test values** in converge.yml (`maxretry: 3`, `bantime: 600`) -- verify.yml then greps for those exact values, coupling the two files

### BUG-01: `_fail2ban_supported_os` variable not defined

`tasks/main.yml` line 17 references `_fail2ban_supported_os` (underscore-prefixed private variable), but `defaults/main.yml` defines `fail2ban_supported_os` (no underscore). There is no `vars/main.yml` or other file that maps between them. This means the OS family assertion will always fail with an undefined variable error.

**Fix required:** Either rename the variable in `tasks/main.yml` to `fail2ban_supported_os`, or create `vars/main.yml` with `_fail2ban_supported_os: "{{ fail2ban_supported_os }}"`. The former is simpler and consistent with other roles (e.g., `git` uses `git_supported_os` directly).

---

## 2. Cross-Platform Analysis

### Package and service naming

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| Package name | `fail2ban` | `fail2ban` |
| Package manager | pacman | apt |
| Install task | `ansible.builtin.package` (generic) | Same -- generic module |
| Service name | `fail2ban` | `fail2ban` |
| Service manager | systemd | systemd |
| Config base path | `/etc/fail2ban/` | `/etc/fail2ban/` |
| Jail drop-in dir | `/etc/fail2ban/jail.d/` | `/etc/fail2ban/jail.d/` |
| Default backend | `auto` (resolves to systemd) | `auto` (resolves to systemd) |
| `os_family` fact | `Archlinux` | `Debian` |
| OS vars file loaded | `vars/archlinux.yml` | `vars/debian.yml` |

### Cross-platform differences

**Essentially none.** Both distros use:
- Same package name (`fail2ban`)
- Same service name (`fail2ban`)
- Same config path (`/etc/fail2ban/jail.d/sshd.conf`)
- Same systemd service manager
- Same `fail2ban-client` CLI for status checks

The only differences are cosmetic:
- Arch installs via pacman, Ubuntu via apt (handled by `ansible.builtin.package`)
- Gentoo uses `net-analyzer/fail2ban` (not tested in molecule -- no Gentoo image)

### Backend behavior

`fail2ban_sshd_backend: auto` resolves to `systemd` on both Arch and Ubuntu when systemd is the init system. In Docker containers, `systemd` backend works because the container runs systemd. The `auto` backend also supports `pyinotify` and `polling` as fallbacks.

### iptables/nftables dependency

fail2ban uses a "ban action" to block IPs. The default action is `iptables-multiport` (Arch) or `nftables-multiport` (Ubuntu 24.04, which ships with nftables as the iptables backend).

In Docker containers:
- `privileged: true` grants access to netfilter
- The Arch systemd image should have iptables available
- fail2ban will start and load jails even if the ban action is not yet exercised (no actual bans during testing)
- `fail2ban-client status sshd` will succeed regardless of ban action availability

In Vagrant VMs:
- Full kernel access -- iptables/nftables work natively
- No special handling needed

---

## 3. Shared Migration

Move `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/` so all scenarios reuse them.

### molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: fail2ban
      vars:
        fail2ban_sshd_maxretry: 3
        fail2ban_sshd_bantime: 600
```

Changes from current `default/converge.yml`:
- **Removed** `os_family == Archlinux` assertion (role supports Arch + Debian)
- **Removed** `fail2ban_enabled: true` and `fail2ban_sshd_enabled: true` (already defaults)
- **Kept** custom test values `maxretry: 3` and `bantime: 600` for deterministic verification

### molecule/shared/verify.yml

Full content designed in Section 6 below.

### molecule/default/molecule.yml (updated)

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
- **Removed** `ANSIBLE_VAULT_PASSWORD_FILE` (role has no vault variables)
- **Changed** playbook paths to `../shared/`
- **Added** `idempotence` to test sequence
- **Added** `callbacks_enabled: profile_tasks` for timing output

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

### Docker-specific concerns

**fail2ban service startup in containers:**
- fail2ban starts a Python server process, not a kernel module -- it runs fine in containers
- The service communicates with iptables/nftables only when actually banning an IP
- `fail2ban-client status` and `fail2ban-client status sshd` work without any bans occurring
- `privileged: true` ensures iptables/nftables access if a ban were triggered

**systemd backend in Docker:**
- `backend = auto` resolves to `systemd` when systemd is the init system
- The fail2ban systemd backend reads journal entries via `systemd-python` / `python-systemd`
- The Arch systemd container runs systemd and has journal access -- this should work
- If `python-systemd` is not installed, fail2ban falls back to `polling` backend (reads log files)

**No SSH daemon in container:**
- The jail monitors SSH login failures, but there is no sshd running in the test container
- This is fine: fail2ban loads the jail configuration and monitors the journal/log, but with no sshd there are no log entries to parse -- the jail simply stays idle
- `fail2ban-client status sshd` reports the jail as active with 0 currently banned IPs

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

    - name: Full system upgrade on Arch (ensures compatibility)
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

### Cross-platform notes for Vagrant

| Aspect | Arch VM (`generic/arch`) | Ubuntu VM (`bento/ubuntu-24.04`) |
|--------|-------------------------|----------------------------------|
| Package | `fail2ban` (pacman) | `fail2ban` (apt) |
| Service | `fail2ban.service` (systemd) | `fail2ban.service` (systemd) |
| Config path | `/etc/fail2ban/jail.d/sshd.conf` | `/etc/fail2ban/jail.d/sshd.conf` |
| Ban action default | `iptables-multiport` | `nftables-multiport` |
| SSH daemon present | Yes (sshd for Vagrant access) | Yes (sshd for Vagrant access) |
| `python-systemd` | Typically installed | `python3-systemd` may need install |
| `os_family` fact | `Archlinux` | `Debian` |

Vagrant VMs have a running SSH daemon (used by Vagrant for provisioning), which means:
- The fail2ban sshd jail will actually have a real target to monitor
- `fail2ban-client status sshd` will show a functioning jail monitoring real SSH logs
- This is a more realistic test than Docker (which has no sshd)

---

## 6. Verify.yml Design

### molecule/shared/verify.yml

```yaml
---
- name: Verify fail2ban role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- Package installed ----

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    - name: Assert fail2ban package is installed
      ansible.builtin.assert:
        that: "'fail2ban' in ansible_facts.packages"
        fail_msg: "fail2ban package not found in installed packages"

    - name: Verify fail2ban-client is available
      ansible.builtin.command:
        cmd: fail2ban-client --version
      register: f2b_verify_version
      changed_when: false
      failed_when: f2b_verify_version.rc != 0

    # ---- Configuration file: existence and permissions ----

    - name: Stat /etc/fail2ban/jail.d/sshd.conf
      ansible.builtin.stat:
        path: /etc/fail2ban/jail.d/sshd.conf
      register: f2b_verify_jail_conf

    - name: Assert jail config exists with correct owner and mode
      ansible.builtin.assert:
        that:
          - f2b_verify_jail_conf.stat.exists
          - f2b_verify_jail_conf.stat.isreg
          - f2b_verify_jail_conf.stat.pw_name == 'root'
          - f2b_verify_jail_conf.stat.gr_name == 'root'
          - f2b_verify_jail_conf.stat.mode == '0644'
        fail_msg: >-
          /etc/fail2ban/jail.d/sshd.conf missing or wrong permissions
          (expected root:root 0644, got {{ f2b_verify_jail_conf.stat.pw_name | default('?') }}:{{
          f2b_verify_jail_conf.stat.gr_name | default('?') }} {{
          f2b_verify_jail_conf.stat.mode | default('?') }})

    # ---- Configuration file: content ----

    - name: Read jail config content
      ansible.builtin.slurp:
        src: /etc/fail2ban/jail.d/sshd.conf
      register: f2b_verify_jail_raw

    - name: Set jail config text fact
      ansible.builtin.set_fact:
        f2b_verify_jail_text: "{{ f2b_verify_jail_raw.content | b64decode }}"

    - name: Assert Ansible managed marker present
      ansible.builtin.assert:
        that: "'Ansible' in f2b_verify_jail_text"
        fail_msg: "Ansible managed marker not found -- config may not be template-generated"

    - name: Assert sshd jail section present
      ansible.builtin.assert:
        that: "'[sshd]' in f2b_verify_jail_text"
        fail_msg: "[sshd] section not found in jail config"

    - name: Assert jail is enabled
      ansible.builtin.assert:
        that: "'enabled = true' in f2b_verify_jail_text"
        fail_msg: "sshd jail is not enabled in config"
      when: fail2ban_sshd_enabled | bool

    - name: Assert maxretry matches converge value
      ansible.builtin.assert:
        that: "'maxretry = 3' in f2b_verify_jail_text"
        fail_msg: "maxretry not set to 3 (converge override value)"

    - name: Assert bantime matches converge value
      ansible.builtin.assert:
        that: "'bantime = 600' in f2b_verify_jail_text"
        fail_msg: "bantime not set to 600 (converge override value)"

    - name: Assert findtime is present
      ansible.builtin.assert:
        that: "'findtime =' in f2b_verify_jail_text"
        fail_msg: "findtime directive missing from jail config"

    - name: Assert backend is present
      ansible.builtin.assert:
        that: "'backend =' in f2b_verify_jail_text"
        fail_msg: "backend directive missing from jail config"

    - name: Assert bantime.increment is configured
      ansible.builtin.assert:
        that: "'bantime.increment = true' in f2b_verify_jail_text"
        fail_msg: "bantime.increment not enabled (expected progressive ban escalation)"
      when: fail2ban_sshd_bantime_increment | bool

    - name: Assert bantime.maxtime is configured
      ansible.builtin.assert:
        that: "'bantime.maxtime =' in f2b_verify_jail_text"
        fail_msg: "bantime.maxtime directive missing (required when bantime.increment is true)"
      when: fail2ban_sshd_bantime_increment | bool

    - name: Assert ignoreip whitelist is present
      ansible.builtin.assert:
        that: "'ignoreip =' in f2b_verify_jail_text"
        fail_msg: "ignoreip whitelist missing from jail config"
      when: fail2ban_ignoreip | length > 0

    - name: Assert localhost is in ignoreip
      ansible.builtin.assert:
        that: "'127.0.0.1/8' in f2b_verify_jail_text"
        fail_msg: "127.0.0.1/8 not in ignoreip whitelist"
      when: "'127.0.0.1/8' in fail2ban_ignoreip"

    # ---- Service state ----

    - name: Check fail2ban service is enabled
      ansible.builtin.command: systemctl is-enabled fail2ban.service
      register: f2b_verify_svc_enabled
      changed_when: false
      failed_when: false
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert fail2ban service is enabled
      ansible.builtin.assert:
        that: f2b_verify_svc_enabled.stdout == 'enabled'
        fail_msg: >-
          fail2ban.service is not enabled
          (got '{{ f2b_verify_svc_enabled.stdout | default("unknown") }}')
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Check fail2ban service is active
      ansible.builtin.command: systemctl is-active fail2ban.service
      register: f2b_verify_svc_active
      changed_when: false
      failed_when: false
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert fail2ban service is active
      ansible.builtin.assert:
        that: f2b_verify_svc_active.stdout == 'active'
        fail_msg: >-
          fail2ban.service is not active
          (got '{{ f2b_verify_svc_active.stdout | default("unknown") }}')
      when: ansible_facts['service_mgr'] == 'systemd'

    # ---- fail2ban-client runtime checks ----

    - name: Check fail2ban-client status
      ansible.builtin.command: fail2ban-client status
      register: f2b_verify_client_status
      changed_when: false
      failed_when: false

    - name: Assert fail2ban-client reports healthy
      ansible.builtin.assert:
        that: f2b_verify_client_status.rc == 0
        fail_msg: >-
          fail2ban-client status failed (rc={{ f2b_verify_client_status.rc }}).
          stderr: {{ f2b_verify_client_status.stderr | default('') }}

    - name: Assert sshd jail is listed
      ansible.builtin.assert:
        that: "'sshd' in f2b_verify_client_status.stdout"
        fail_msg: >-
          sshd jail not listed in fail2ban-client status output.
          stdout: {{ f2b_verify_client_status.stdout }}
      when: fail2ban_sshd_enabled | bool

    - name: Check fail2ban-client status sshd
      ansible.builtin.command: fail2ban-client status sshd
      register: f2b_verify_sshd_status
      changed_when: false
      failed_when: false
      when: fail2ban_sshd_enabled | bool

    - name: Assert sshd jail is active
      ansible.builtin.assert:
        that:
          - f2b_verify_sshd_status.rc == 0
          - "'sshd' in f2b_verify_sshd_status.stdout"
        fail_msg: >-
          fail2ban sshd jail status check failed.
          rc={{ f2b_verify_sshd_status.rc }},
          stdout: {{ f2b_verify_sshd_status.stdout | default('') }}
      when: fail2ban_sshd_enabled | bool

    # ---- Diagnostic (informational, no assertions) ----

    - name: Diagnostic -- fail2ban-client status output
      ansible.builtin.debug:
        var: f2b_verify_client_status.stdout_lines
      when: f2b_verify_client_status.rc == 0

    - name: Diagnostic -- sshd jail status output
      ansible.builtin.debug:
        var: f2b_verify_sshd_status.stdout_lines
      when:
        - fail2ban_sshd_enabled | bool
        - f2b_verify_sshd_status.rc == 0

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          fail2ban verify passed: package installed, jail config deployed
          (root:root 0644) with correct directives, service enabled and active,
          fail2ban-client reports sshd jail active.
```

### Assertion summary table

| # | Assertion | Cross-platform | When guard |
|---|-----------|---------------|------------|
| 1 | fail2ban package in package_facts | Both | always |
| 2 | `fail2ban-client --version` succeeds | Both | always |
| 3 | `/etc/fail2ban/jail.d/sshd.conf` exists, root:root 0644 | Both | always |
| 4 | Ansible managed marker present | Both | always |
| 5 | `[sshd]` section present | Both | always |
| 6 | `enabled = true` | Both | `fail2ban_sshd_enabled` |
| 7 | `maxretry = 3` (converge override) | Both | always |
| 8 | `bantime = 600` (converge override) | Both | always |
| 9 | `findtime =` directive present | Both | always |
| 10 | `backend =` directive present | Both | always |
| 11 | `bantime.increment = true` | Both | `fail2ban_sshd_bantime_increment` |
| 12 | `bantime.maxtime =` present | Both | `fail2ban_sshd_bantime_increment` |
| 13 | `ignoreip =` whitelist present | Both | `fail2ban_ignoreip \| length > 0` |
| 14 | `127.0.0.1/8` in ignoreip | Both | `'127.0.0.1/8' in fail2ban_ignoreip` |
| 15 | Service enabled (systemctl) | Both | `service_mgr == 'systemd'` |
| 16 | Service active (systemctl) | Both | `service_mgr == 'systemd'` |
| 17 | `fail2ban-client status` rc 0 | Both | always |
| 18 | sshd listed in client status | Both | `fail2ban_sshd_enabled` |
| 19 | `fail2ban-client status sshd` succeeds | Both | `fail2ban_sshd_enabled` |
| 20 | sshd jail active in client output | Both | `fail2ban_sshd_enabled` |

No assertions require `ansible_distribution`-specific guards because the fail2ban
configuration, service name, config path, and CLI are identical on Arch and Ubuntu.

### Design decisions

**Using `systemctl` commands instead of `service_facts`:** The current verify.yml uses `service_facts` which works for `.service` units but the explicit `systemctl is-enabled` / `systemctl is-active` pattern is more reliable and consistent with the firewall plan's approach.

**`vars_files: ../../defaults/main.yml`:** Loads the role's default variables so `when:` guards can reference `fail2ban_sshd_enabled`, `fail2ban_sshd_bantime_increment`, etc. The converge playbook overrides `maxretry` and `bantime`, but other variables retain their defaults.

**Hardcoded converge values in assertions:** The verify checks `maxretry = 3` and `bantime = 600` which are set in `converge.yml`. This couples the two files but ensures the template is actually rendering the overridden values (not just defaults). This is the existing pattern and works well.

---

## 7. Implementation Order

### Step 1: Fix BUG-01 -- variable name mismatch

In `ansible/roles/fail2ban/tasks/main.yml` line 17, change `_fail2ban_supported_os` to `fail2ban_supported_os` to match the variable defined in `defaults/main.yml`.

### Step 2: Create shared directory and playbooks

```
mkdir -p ansible/roles/fail2ban/molecule/shared/
```

Create `molecule/shared/converge.yml` (simplified -- no Arch assertion, no vault).
Create `molecule/shared/verify.yml` (comprehensive -- from Section 6).

### Step 3: Update molecule/default/molecule.yml

- Remove `ANSIBLE_VAULT_PASSWORD_FILE`
- Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
- Add `callbacks_enabled: profile_tasks`
- Add `idempotence` to test sequence

### Step 4: Delete old converge.yml and verify.yml from default/

```
rm ansible/roles/fail2ban/molecule/default/converge.yml
rm ansible/roles/fail2ban/molecule/default/verify.yml
```

### Step 5: Create Docker scenario

```
mkdir -p ansible/roles/fail2ban/molecule/docker/
```

Create `molecule/docker/molecule.yml` and `molecule/docker/prepare.yml` per Section 4.

### Step 6: Create Vagrant scenario

```
mkdir -p ansible/roles/fail2ban/molecule/vagrant/
```

Create `molecule/vagrant/molecule.yml` and `molecule/vagrant/prepare.yml` per Section 5.

### Step 7: Test locally

```bash
# Default scenario (localhost, Arch only)
cd ansible/roles/fail2ban && molecule test -s default

# Docker scenario (Arch systemd container)
cd ansible/roles/fail2ban && molecule test -s docker

# Vagrant scenario (Arch + Ubuntu VMs, requires libvirt)
cd ansible/roles/fail2ban && molecule test -s vagrant
```

### Step 8: Verify idempotence

The role should be idempotent:
- First run: installs fail2ban, deploys jail config, enables/starts service, runs verify
- Second run: no changes (all tasks report `ok`)

Potential idempotence concern: the `tasks/verify.yml` uses `ansible.builtin.command` which always reports `ok` (not `changed`) due to `changed_when: false`. This is correct.

The `ansible_managed` comment in the template includes a timestamp, but Ansible's `ansible_managed` string is deterministic within a single molecule run. The idempotence check (two consecutive converge runs in the same session) should produce the same timestamp. If not, add `ansible_managed: "Managed by Ansible"` in provisioner config.

---

## 8. Risks / Notes

### fail2ban requires a running init system

fail2ban is a long-running daemon (Python server process). It needs:
- A working init system to start/manage the service (systemd in our case)
- Access to journal (for `systemd` backend) or log files (for `polling` backend)

The Docker scenario uses a systemd container (`command: /usr/lib/systemd/systemd`) which satisfies both requirements. Non-systemd containers would need `backend = polling` and a manually created log file.

### fail2ban in Docker without sshd

The test containers have no SSH daemon. This means:
- The sshd jail loads but has nothing to monitor
- `fail2ban-client status sshd` reports 0 currently banned, 0 total banned
- The jail is listed as active -- this is the correct behavior

This is sufficient for testing that the role correctly installs, configures, and starts fail2ban with the sshd jail. Functional testing (actual ban/unban) would require an integration scenario with a running sshd and simulated failed logins.

### fail2ban backend detection

`backend = auto` in the jail config makes fail2ban auto-detect the best backend:
1. `systemd` -- if `python-systemd` / `python3-systemd` is installed and systemd is running
2. `pyinotify` -- if `python-pyinotify` is installed
3. `polling` -- fallback, reads log files

On Arch, `python-systemd` is a dependency of `fail2ban`. On Ubuntu, `python3-systemd` is pulled in by the `fail2ban` package. Both should resolve to `systemd` backend.

If `python-systemd` is missing in the Docker image, fail2ban will fall back to `polling` and look for `/var/log/auth.log` (Ubuntu) or `/var/log/secure` (RHEL). Since neither exists in a fresh container, the jail may report errors in the log but will still show as "active" in `fail2ban-client status`.

### Vagrant Arch box stale keyring

**Risk:** `generic/arch` Vagrant boxes ship with stale pacman keyring. Package installs fail with signature errors.

**Mitigation:** `prepare.yml` temporarily disables signature checking, updates the keyring, then re-enables signatures. This is the established pattern from the `package_manager` vagrant scenario.

### Idempotence with `tasks/verify.yml`

The role includes `tasks/verify.yml` which runs `fail2ban-client status` and `fail2ban-client status sshd` as part of the converge. These use `changed_when: false` and will not affect idempotence.

### BUG-01 must be fixed before testing

The `_fail2ban_supported_os` variable mismatch in `tasks/main.yml` will cause the OS assertion to fail with an undefined variable error on every run. This must be fixed in Step 1 before any molecule scenario can succeed.

### `common` role dependency for report tasks

The `tasks/main.yml` includes `common` role's `report_phase.yml` and `report_render.yml`. These are tagged `report` and skipped in Docker/Vagrant scenarios via `skip-tags: report`. The default (localhost) scenario does NOT skip tags, so the `common` role must be available at `ANSIBLE_ROLES_PATH`. Since `ANSIBLE_ROLES_PATH` points to `${MOLECULE_PROJECT_DIRECTORY}/../` (the parent roles directory), the `common` role will be found.

However, if the default scenario adds `skip-tags: report` in the future, the common role dependency can be ignored entirely.

### No Ubuntu in meta/main.yml

The current `meta/main.yml` lists ArchLinux, Debian, Ubuntu, Fedora, and GenericLinux as platforms. This already covers both Vagrant test targets. No change needed.

### `fail2ban_supported_os` vs tested platforms

`defaults/main.yml` declares support for: Archlinux, Debian, RedHat, Void, Gentoo.
`meta/main.yml` declares platforms: ArchLinux, Debian, Ubuntu, Fedora, GenericLinux.

These lists are inconsistent (meta includes Ubuntu separately while defaults has Debian which covers Ubuntu via `os_family`, meta includes Fedora while defaults has RedHat, etc.). This is not a blocker for testing but should be harmonized eventually. The `os_family` fact maps Ubuntu to `Debian` and Fedora to `RedHat`, so the defaults list is the operationally correct one.

---

## File tree after implementation

```
ansible/roles/fail2ban/
  defaults/main.yml              (unchanged)
  handlers/main.yml              (unchanged)
  meta/main.yml                  (unchanged)
  tasks/
    main.yml                     (FIXED: _fail2ban_supported_os -> fail2ban_supported_os)
    install.yml                  (unchanged)
    configure.yml                (unchanged)
    verify.yml                   (unchanged)
  templates/
    jail_sshd.conf.j2            (unchanged)
  vars/
    archlinux.yml                (unchanged)
    debian.yml                   (unchanged)
    gentoo.yml                   (unchanged)
    redhat.yml                   (unchanged)
    void.yml                     (unchanged)
  molecule/
    shared/
      converge.yml               (NEW -- cross-platform, no vault, no Arch assertion)
      verify.yml                 (NEW -- 20 assertions, cross-platform)
    default/
      molecule.yml               (UPDATED -- point to shared/, remove vault, add idempotence)
    docker/
      molecule.yml               (NEW -- arch-systemd container)
      prepare.yml                (NEW -- pacman update_cache)
    vagrant/
      molecule.yml               (NEW -- Arch + Ubuntu VMs via libvirt)
      prepare.yml                (NEW -- Python bootstrap, keyring refresh, apt cache)
```
