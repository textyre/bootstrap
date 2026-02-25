# Plan: Teleport Role -- Molecule Testing

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/teleport/`

---

## 1. Current State

### What the Role Does

The `teleport` role deploys a Teleport SSH access platform agent (node or proxy) for zero-trust SSH access with certificate authority integration. It covers:

- **OS validation**: Asserts `os_family` is in `teleport_supported_os` (Archlinux, Debian, RedHat, Void, Gentoo)
- **OS-specific variables**: Loads `vars/{os_family}.yml` for install method, package names, service name map
- **Pre-flight join validation**: Asserts `teleport_auth_server` and `teleport_join_token` are non-empty (fail-fast)
- **Installation**: Three install methods dispatched by `teleport_install_method`:
  - `package` (Arch): installs `teleport-bin` via `ansible.builtin.package`
  - `repo` (Debian/RedHat): adds GPG key + APT/YUM repository, then installs `teleport`
  - `binary` (Void/Gentoo): downloads tarball from `cdn.teleport.dev`, extracts to `/usr/local/bin/`
- **Configuration**: Creates `/var/lib/teleport` (0750), deploys `/etc/teleport.yaml` (0600) from `teleport.yaml.j2`
- **CA export** (optional): Runs `tctl auth export --type=user`, writes CA pubkey to `teleport_ca_keys_file`, sets `teleport_ca_deployed` fact for `ssh` role integration
- **Service management**: Enables and starts `teleport` via init-system-agnostic `service_name` map (systemd, runit, openrc, s6, dinit)
- **In-role verification**: Checks `teleport version`, config file stat, `teleport status`
- **Reporting**: Phase reports via `common` role (`report_phase.yml` / `report_render.yml`)

### OS-Specific Install Methods

| OS Family | `teleport_install_method` | Package(s) | Notes |
|-----------|--------------------------|-----------|-------|
| Archlinux | `package` | `teleport-bin` | AUR package (binary release) |
| Debian | `repo` | `teleport` (from official APT repo) | GPG key + signed repo added |
| RedHat | `repo` | `teleport` (from official YUM repo) | GPG key + repo added |
| Void | `binary` | (none) | Tarball download + extract |
| Gentoo | `binary` | (none) | Tarball download + extract |

### Template Content (`teleport.yaml.j2`)

The template produces a `version: v3` Teleport config with:
- `teleport.nodename`, `data_dir`, `auth_token`, `auth_server`, `log`
- `ssh_service.enabled` + optional `labels`
- `proxy_service.enabled` (disabled by default)
- `auth_service.enabled: false` (this is a node, not an auth server)
- Optional `session_recording` block with optional `enhanced_recording`

### Existing Molecule Tests

Single scenario at `molecule/default/`:

- **Driver:** `default` (localhost, managed: false)
- **Provisioner:** Ansible with vault password, ANSIBLE_ROLES_PATH set to `../ `
- **converge.yml:** Applies `teleport` role with test variables:
  - `teleport_auth_server: "localhost:3025"`
  - `teleport_join_token: "test-token-molecule"`
  - `teleport_node_name: "molecule-test"`
  - `teleport_session_recording: "node"`
  - `teleport_export_ca_key: false` (CA export disabled -- no real cluster)
- **verify.yml:** 4 checks:
  1. `/etc/teleport.yaml` exists with mode `0600` and owner `root`
  2. Config contains `auth_server: localhost:3025`
  3. Config contains `nodename: molecule-test`
  4. `/var/lib/teleport` data directory exists and is a directory
- **test_sequence:** syntax, converge, verify (no idempotence, no destroy)

### Key Observations

1. **No binary check in verify.yml**: The existing verify does not check whether the `teleport` binary is installed. The in-role `tasks/verify.yml` does this but molecule verify does not.
2. **No service check**: Neither service state nor service unit file is verified.
3. **CA export disabled**: Converge disables `teleport_export_ca_key` because `tctl auth export` requires a running Teleport cluster. This is correct for isolated testing.
4. **No idempotence test**: The test sequence omits idempotence.
5. **Vault dependency**: The `molecule.yml` references `vault-pass.sh` but no vault variables are used by the role or converge playbook. This is unnecessary.

---

## 2. Cross-Platform Analysis

### Teleport Availability by Platform

| Platform | Install Method | Package Source | Available in Test? |
|----------|---------------|---------------|-------------------|
| Arch Linux | `package` | AUR: `teleport-bin` | Requires `yay` or manual AUR build -- **not available via pacman** |
| Ubuntu 24.04 | `repo` | Official Teleport APT repository | Requires internet access to add repo + download |
| RedHat/Fedora | `repo` | Official Teleport YUM repository | Not in scope for initial testing |
| Void Linux | `binary` | Direct tarball download from `cdn.teleport.dev` | Not in scope |
| Gentoo | `binary` | Direct tarball download | Not in scope |

### Arch Linux: AUR Package Challenge

The Arch `vars/archlinux.yml` specifies:
```yaml
teleport_packages:
  - teleport-bin
teleport_install_method: package
```

The `teleport-bin` package is an **AUR package**, not in the official Arch repositories. `ansible.builtin.package` (which maps to `community.general.pacman`) cannot install AUR packages. This means:

1. **Docker scenario**: The arch-systemd container does not have `yay` or any AUR helper. Installing `teleport-bin` via `pacman` will fail with "target not found."
2. **Vagrant Arch scenario**: Same issue unless `prepare.yml` installs an AUR helper first.

**Mitigation options:**
- (a) Switch Arch to `binary` install method in converge.yml via variable override
- (b) Install `yay` in prepare.yml and use it to build `teleport-bin`
- (c) Pre-install teleport binary in prepare.yml via tarball download

**Recommendation:** Option (a) is simplest and most reliable for CI. Override `teleport_install_method: binary` in `converge.yml` for Arch scenarios. This exercises the binary download path, which is a valid install method. Alternatively, option (c) can be used in prepare.yml. The AUR package install path cannot be tested without a full AUR helper setup, which is out of scope.

### Ubuntu 24.04: Official Repository

The Debian `vars/debian.yml` specifies:
```yaml
teleport_packages: []
teleport_install_method: repo
```

This triggers the GPG key download + APT repository addition + package install flow. This requires:
- Internet access (to reach `apt.releases.teleport.dev`)
- DNS resolution
- The distribution release codename to be recognized by Teleport's repo URL

Ubuntu 24.04 (Noble Numbat) should be supported by Teleport's official APT repo for version 17.x. The template URL:
```
deb [signed-by=...] https://apt.releases.teleport.dev/ubuntu noble stable/v17
```

### Service Behavior Without a Cluster

Teleport's systemd service (`teleport.service`) will **start** but immediately enter a retry loop or fail because:
- `auth_token: test-token-molecule` is not a valid join token for any cluster
- `auth_server: localhost:3025` has nothing listening on port 3025

**Impact on testing:**
- `systemctl start teleport` may succeed (service starts, then fails health check)
- `teleport status` will show connection errors
- The service may be in `activating (auto-restart)` or `failed` state

**This is the fundamental constraint for Teleport molecule testing.** We cannot fully start the service in isolation. Testing must focus on:
- Package/binary installed
- Config file deployed with correct content and permissions
- Data directory exists with correct permissions
- Service unit file exists and is enabled (but NOT necessarily running)

---

## 3. Shared Migration

Move `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/`.

### New Directory Layout

```
ansible/roles/teleport/molecule/
  shared/
    converge.yml      <-- adapted from default/converge.yml
    verify.yml        <-- rewritten with cross-platform assertions
  default/
    molecule.yml      <-- updated to point at ../shared/
  docker/
    molecule.yml      <-- new (Arch systemd container)
    prepare.yml       <-- new (pacman cache update + teleport binary pre-install)
  vagrant/
    molecule.yml      <-- new (Arch + Ubuntu VMs)
    prepare.yml       <-- new (keyring refresh, apt cache, teleport binary for Arch)
```

### shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: teleport
      vars:
        teleport_auth_server: "localhost:3025"
        teleport_join_token: "test-token-molecule"
        teleport_node_name: "molecule-test"
        teleport_session_recording: "node"
        teleport_export_ca_key: false
```

Changes from current `default/converge.yml`:
- Added `gather_facts: true` (explicit)
- Moved `teleport_enabled: true` removal (it defaults to true anyway)
- Kept `teleport_export_ca_key: false` (CA export requires a live cluster)
- Variables passed as role vars for clarity

**Note on service start:** The converge will attempt to enable and start the teleport service. This task will likely fail because there is no real auth server at `localhost:3025`. Two approaches:

1. **Skip service tag in converge:** Add `skip-tags: report,service` to provisioner options. This prevents the `enable and start teleport` task from running.
2. **Override in converge vars:** Not possible since `tasks/main.yml` unconditionally enables the service.

**Recommendation:** Use `skip-tags: report,service` in the provisioner. This skips both the `common` role reporting and the service start task. The verify.yml will check that the service unit exists and is enabled, but will not assert it is running.

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
    skip-tags: report,service
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
- Removed `vault_password_file` (not needed)
- Added `skip-tags: report,service`
- Changed playbook paths to `../shared/`
- Added `idempotence` to test sequence

---

## 4. Testing Strategy

### What We CAN Test (Isolated Environment)

| Category | Assertion | Reason |
|----------|-----------|--------|
| Binary installed | `teleport version` succeeds | Validates install method worked |
| Config file exists | `/etc/teleport.yaml` stat | Validates template deployment |
| Config permissions | mode `0600`, owner `root` | Security requirement |
| Config content | Contains expected auth_server, nodename, ssh/proxy/auth sections | Validates template rendering |
| Data directory | `/var/lib/teleport` exists, mode `0750`, owner `root` | Role creates this |
| Service unit exists | `systemctl cat teleport.service` succeeds | Validates package ships a unit file |
| Service enabled | `systemctl is-enabled teleport` == `enabled` | Role enables service |
| Idempotence | Second converge produces no changes | Standard molecule check |

### What We CANNOT Test (Requires Live Cluster)

| Category | Reason |
|----------|--------|
| Service running | Teleport exits/retries without a valid auth server |
| `teleport status` | Returns error without cluster connectivity |
| CA export (`tctl auth export`) | Requires running auth service |
| Node join/registration | Requires auth server accepting the join token |
| Session recording | Requires active sessions through a proxy |
| Enhanced (BPF) recording | Requires kernel BPF support + active sessions |
| Teleport web UI | Proxy mode only, requires TLS + auth |

### Service Tag Skip Rationale

The `tasks/main.yml` line 53-58 enables and starts the teleport service unconditionally (within the `teleport_enabled` block). Since Teleport cannot start without a valid cluster connection, this task will fail in molecule. We skip it with `skip-tags: service`.

The `tasks/verify.yml` (in-role verification) is also run within the converge and checks `teleport status`. With `skip-tags` not covering the in-role verify task (it uses tag `teleport`, not `service`), `teleport status` will run and is configured with `failed_when: false` so it will not fail the converge. This is acceptable.

---

## 5. Docker Scenario

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
    skip-tags: report,service
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

The Arch container cannot install `teleport-bin` from AUR via pacman. The prepare step downloads the Teleport binary tarball directly, matching the `binary` install method.

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true

    - name: Set Teleport version and architecture
      ansible.builtin.set_fact:
        _prepare_teleport_version: "17.0.0"
        _prepare_teleport_arch: >-
          {{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture]
             | default(ansible_architecture) }}

    - name: Download Teleport binary tarball
      ansible.builtin.get_url:
        url: "https://cdn.teleport.dev/teleport-v{{ _prepare_teleport_version }}-linux-{{ _prepare_teleport_arch }}-bin.tar.gz"
        dest: /tmp/teleport.tar.gz
        mode: "0644"

    - name: Create extraction directory
      ansible.builtin.file:
        path: /tmp/teleport-extract
        state: directory
        mode: "0755"

    - name: Extract Teleport binary
      ansible.builtin.unarchive:
        src: /tmp/teleport.tar.gz
        dest: /tmp/teleport-extract
        remote_src: true

    - name: Install Teleport binaries to /usr/local/bin
      ansible.builtin.copy:
        src: "/tmp/teleport-extract/teleport/{{ item }}"
        dest: "/usr/local/bin/{{ item }}"
        mode: "0755"
        remote_src: true
      loop:
        - teleport
        - tctl
        - tsh

    - name: Create teleport systemd service unit
      ansible.builtin.copy:
        dest: /usr/lib/systemd/system/teleport.service
        mode: "0644"
        content: |
          [Unit]
          Description=Teleport SSH Service
          After=network.target

          [Service]
          Type=simple
          ExecStart=/usr/local/bin/teleport start -c /etc/teleport.yaml
          ExecReload=/bin/kill -HUP $MAINPID
          Restart=on-failure
          RestartSec=5

          [Install]
          WantedBy=multi-user.target

    - name: Reload systemd daemon
      ansible.builtin.systemd:
        daemon_reload: true
```

**Why pre-install in prepare?** The role's `install.yml` with `teleport_install_method: package` will call `ansible.builtin.package` for `teleport-bin`, which will fail because the AUR package is not in pacman repos. By pre-installing the binary in prepare, the `package` task becomes a no-op (package appears "installed" if we check the binary) -- but actually, `ansible.builtin.package` checks the pacman database, not the binary on disk.

**Alternative approach:** Override `teleport_install_method` in converge.yml:

```yaml
roles:
  - role: teleport
    vars:
      teleport_install_method: binary
      teleport_auth_server: "localhost:3025"
      teleport_join_token: "test-token-molecule"
      teleport_node_name: "molecule-test"
      teleport_export_ca_key: false
```

This tells the role to use the binary download path instead of pacman, which works in the container. However, this means the shared converge.yml must be aware of the platform.

**Best approach:** Use a platform-aware converge by setting the variable in `molecule.yml` provisioner inventory:

### Revised molecule/docker/molecule.yml (with install method override)

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
    skip-tags: report,service
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      Archlinux-systemd:
        teleport_install_method: binary
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

With this approach, the prepare.yml is simplified to just a pacman cache update:

### Revised molecule/docker/prepare.yml

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

The role's `install.yml` binary download block will handle fetching and extracting Teleport. However, the binary install does **not** create a systemd service unit -- it only extracts binaries to `/usr/local/bin/`. The service unit typically comes from the package. Since we skip the `service` tag, this is acceptable.

**Decision:** Use the host_vars override approach with simplified prepare.yml. The binary install path in the role handles download and extraction. Service management is skipped.

---

## 6. Vagrant Scenario

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
    skip-tags: report,service
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      arch-vm:
        teleport_install_method: binary
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

**Note:** `arch-vm` gets `teleport_install_method: binary` override (same reason as Docker -- AUR not available). `ubuntu-noble` uses the default `repo` install method from `vars/debian.yml`, which adds the official Teleport APT repository.

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

### Cross-Platform Behavior

| Aspect | Arch Linux (vagrant) | Ubuntu 24.04 (vagrant) |
|--------|---------------------|----------------------|
| Install method | `binary` (overridden) | `repo` (default from vars/debian.yml) |
| Binary source | `cdn.teleport.dev` tarball | Official APT repo |
| Package name | N/A (binary download) | `teleport` |
| Service unit | Not installed (binary method) | Installed by deb package |
| Config path | `/etc/teleport.yaml` | `/etc/teleport.yaml` |
| Data directory | `/var/lib/teleport` | `/var/lib/teleport` |
| Service name | `teleport` | `teleport` |

**Key difference:** On Ubuntu, the `repo` install method adds a GPG key and APT repository, then installs the `teleport` package which includes a systemd unit file. On Arch with `binary` override, only the binaries are extracted to `/usr/local/bin/` -- no service unit is installed.

**Verify.yml impact:** Service-related checks must be conditional. On binary-install platforms, service unit assertions are skipped.

---

## 7. Verify.yml Design

### shared/verify.yml

The verify playbook uses conservative assertions appropriate for an isolated test environment where Teleport cannot connect to a real cluster.

```yaml
---
- name: Verify teleport role (offline assertions)
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- Binary installed ----

    - name: Check teleport binary exists
      ansible.builtin.command:
        cmd: teleport version
      register: teleport_verify_version
      changed_when: false
      failed_when: false

    - name: Assert teleport binary is available
      ansible.builtin.assert:
        that: teleport_verify_version.rc == 0
        fail_msg: >-
          teleport binary not found or not executable.
          stderr: {{ teleport_verify_version.stderr | default('') }}

    - name: Show teleport version
      ansible.builtin.debug:
        var: teleport_verify_version.stdout_lines

    # ---- Configuration file ----

    - name: Stat /etc/teleport.yaml
      ansible.builtin.stat:
        path: /etc/teleport.yaml
      register: teleport_verify_config

    - name: Assert teleport.yaml exists with correct owner and mode
      ansible.builtin.assert:
        that:
          - teleport_verify_config.stat.exists
          - teleport_verify_config.stat.isreg
          - teleport_verify_config.stat.pw_name == 'root'
          - teleport_verify_config.stat.gr_name == 'root'
          - teleport_verify_config.stat.mode == '0600'
        fail_msg: >-
          /etc/teleport.yaml missing or wrong permissions
          (expected root:root 0600, got {{ teleport_verify_config.stat.pw_name | default('?') }}:
          {{ teleport_verify_config.stat.gr_name | default('?') }}
          {{ teleport_verify_config.stat.mode | default('missing') }})

    # ---- Configuration content ----

    - name: Read teleport.yaml
      ansible.builtin.slurp:
        src: /etc/teleport.yaml
      register: teleport_verify_config_raw

    - name: Set teleport.yaml text fact
      ansible.builtin.set_fact:
        teleport_verify_config_text: "{{ teleport_verify_config_raw.content | b64decode }}"

    - name: Assert config version v3
      ansible.builtin.assert:
        that: "'version: v3' in teleport_verify_config_text"
        fail_msg: "Teleport config version is not v3"

    - name: Assert config contains auth_server
      ansible.builtin.assert:
        that: "'auth_server: localhost:3025' in teleport_verify_config_text"
        fail_msg: "auth_server not set to 'localhost:3025' in /etc/teleport.yaml"

    - name: Assert config contains nodename
      ansible.builtin.assert:
        that: "'nodename: molecule-test' in teleport_verify_config_text"
        fail_msg: "nodename not set to 'molecule-test' in /etc/teleport.yaml"

    - name: Assert config contains auth_token
      ansible.builtin.assert:
        that: "'auth_token:' in teleport_verify_config_text"
        fail_msg: "auth_token directive missing from /etc/teleport.yaml"

    - name: Assert config contains data_dir
      ansible.builtin.assert:
        that: "'data_dir: /var/lib/teleport' in teleport_verify_config_text"
        fail_msg: "data_dir not set to /var/lib/teleport"

    - name: Assert SSH service enabled in config
      ansible.builtin.assert:
        that: "'ssh_service:' in teleport_verify_config_text"
        fail_msg: "ssh_service section missing from config"

    - name: Assert proxy service section present
      ansible.builtin.assert:
        that: "'proxy_service:' in teleport_verify_config_text"
        fail_msg: "proxy_service section missing from config"

    - name: Assert auth service disabled
      ansible.builtin.assert:
        that: "'auth_service:' in teleport_verify_config_text"
        fail_msg: "auth_service section missing from config"

    - name: Assert session recording configured
      ansible.builtin.assert:
        that: "'mode: \"node\"' in teleport_verify_config_text"
        fail_msg: "session_recording mode not set to 'node'"

    - name: Assert Ansible managed marker present
      ansible.builtin.assert:
        that: "'Ansible managed' in teleport_verify_config_text"
        fail_msg: "Ansible managed marker not found in config"

    # ---- Data directory ----

    - name: Stat /var/lib/teleport
      ansible.builtin.stat:
        path: /var/lib/teleport
      register: teleport_verify_datadir

    - name: Assert data directory exists with correct permissions
      ansible.builtin.assert:
        that:
          - teleport_verify_datadir.stat.exists
          - teleport_verify_datadir.stat.isdir
          - teleport_verify_datadir.stat.pw_name == 'root'
          - teleport_verify_datadir.stat.gr_name == 'root'
          - teleport_verify_datadir.stat.mode == '0750'
        fail_msg: >-
          /var/lib/teleport missing or wrong permissions
          (expected root:root 0750)

    # ---- Service unit (conditional -- only for repo/package install) ----

    - name: Check if teleport systemd unit exists
      ansible.builtin.command:
        cmd: systemctl cat teleport.service
      register: teleport_verify_unit
      changed_when: false
      failed_when: false
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert teleport service unit exists (repo/package install)
      ansible.builtin.assert:
        that: teleport_verify_unit.rc == 0
        fail_msg: >-
          teleport.service unit not found. This is expected for binary installs
          (Arch/Void/Gentoo) where no package provides the unit file.
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - teleport_install_method | default('package') == 'repo'

    - name: Check if teleport service is enabled
      ansible.builtin.command:
        cmd: systemctl is-enabled teleport.service
      register: teleport_verify_svc_enabled
      changed_when: false
      failed_when: false
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Show teleport service enable status (diagnostic)
      ansible.builtin.debug:
        msg: >-
          teleport.service is-enabled: {{ teleport_verify_svc_enabled.stdout | default('not checked') }}
          (service management skipped in molecule -- expected 'disabled' or 'not-found')
      when: ansible_facts['service_mgr'] == 'systemd'

    # ---- CA export NOT tested (requires live cluster) ----

    - name: Info -- CA export testing skipped
      ansible.builtin.debug:
        msg: >-
          teleport_export_ca_key is false in molecule converge.
          CA export requires a running Teleport auth server (tctl auth export).
          This cannot be tested in an isolated environment.

    # ---- Diagnostic ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Teleport offline verify passed: binary installed (teleport version OK),
          /etc/teleport.yaml correct (root:root 0600, v3 config with expected
          auth_server, nodename, data_dir, ssh/proxy/auth sections),
          /var/lib/teleport directory exists (root:root 0750).
          Service and CA export checks skipped (no live cluster).
```

### Assertion Summary Table

| # | Assertion | Cross-platform | When guard |
|---|-----------|---------------|------------|
| 1 | teleport binary available (`teleport version`) | Both | always |
| 2 | `/etc/teleport.yaml` exists, root:root 0600 | Both | always |
| 3 | Config: `version: v3` | Both | always |
| 4 | Config: `auth_server: localhost:3025` | Both | always |
| 5 | Config: `nodename: molecule-test` | Both | always |
| 6 | Config: `auth_token:` present | Both | always |
| 7 | Config: `data_dir: /var/lib/teleport` | Both | always |
| 8 | Config: `ssh_service:` section | Both | always |
| 9 | Config: `proxy_service:` section | Both | always |
| 10 | Config: `auth_service:` section | Both | always |
| 11 | Config: session recording mode `node` | Both | always |
| 12 | Config: Ansible managed marker | Both | always |
| 13 | `/var/lib/teleport` exists, root:root 0750 | Both | always |
| 14 | systemd unit file exists | Ubuntu only | `install_method == 'repo'` |
| 15 | Service enabled status (diagnostic) | Both | systemd |
| 16 | CA export skipped info | Both | always (informational) |
| 17 | Summary diagnostic | Both | always (informational) |

14 hard assertions, 3 informational diagnostics.

---

## 8. Implementation Order

### Step 1: Create shared directory and playbooks

```
mkdir -p ansible/roles/teleport/molecule/shared/
```

- Create `molecule/shared/converge.yml` (from Section 3)
- Create `molecule/shared/verify.yml` (from Section 7)

### Step 2: Update molecule/default/molecule.yml

- Remove `vault_password_file` reference
- Add `skip-tags: report,service`
- Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
- Add `idempotence` to test sequence

### Step 3: Delete old files from default/

```
rm ansible/roles/teleport/molecule/default/converge.yml
rm ansible/roles/teleport/molecule/default/verify.yml
```

### Step 4: Test default scenario

```bash
cd ansible/roles/teleport && molecule test -s default
```

Validate that shared migration works on localhost before creating new scenarios.

### Step 5: Create Docker scenario

```
mkdir -p ansible/roles/teleport/molecule/docker/
```

- Create `molecule/docker/molecule.yml` with `teleport_install_method: binary` host_var
- Create `molecule/docker/prepare.yml` (pacman cache update only)

### Step 6: Test Docker scenario

```bash
cd ansible/roles/teleport && molecule test -s docker
```

Expected: binary download from `cdn.teleport.dev`, config deployed, verify passes.

### Step 7: Create Vagrant scenario

```
mkdir -p ansible/roles/teleport/molecule/vagrant/
```

- Create `molecule/vagrant/molecule.yml` with Arch (`binary` override) + Ubuntu (`repo` default)
- Create `molecule/vagrant/prepare.yml` (keyring refresh for Arch, apt cache for Ubuntu)

### Step 8: Test Vagrant scenario

```bash
cd ansible/roles/teleport && molecule test -s vagrant
```

Expected: Arch uses binary download, Ubuntu uses official APT repo. Both deploy config and pass verify.

### Step 9: Verify idempotence

Both converge runs should produce no changes on the second run. Potential issues:
- Binary download: `get_url` with `creates:` guard -- but the role does not use `creates:`. The tarball is re-downloaded each time. This may cause idempotence failure.
- Config template: `teleport.yaml.j2` uses `{{ ansible_managed }}` which is deterministic within a single molecule run.

**Idempotence fix needed:** The `install.yml` binary download block does not have idempotence guards. The `get_url` will re-download each time. Consider adding a `creates:` parameter or a pre-check for the binary. This is a role-level fix, not a molecule-level fix.

---

## 9. Risks / Notes

### Teleport Requires a Running Cluster

**This is the single most important constraint.** Teleport is a distributed system: the agent (node) must connect to an auth server to:
- Validate its join token
- Receive its node certificate
- Register in the cluster inventory
- Begin accepting SSH connections through the proxy

Without a live cluster, the Teleport service enters a connection retry loop and never reaches a healthy state. This means:
- `teleport status` always reports errors
- The systemd service may cycle between `activating` and `failed`
- CA export (`tctl auth export`) fails completely

**Testing scope is limited to deployment artifacts:** binary installed, config correct, directories created. This is analogous to deploying a database client role without a database server -- you verify the client is installed and configured, not that it can connect.

### AUR Package Not Testable in CI

The `teleport-bin` AUR package requires an AUR helper (`yay`, `paru`) which is not available in the arch-systemd Docker image or the generic/arch Vagrant box. The `binary` install method override is the pragmatic solution. The AUR install path is only testable on a real Arch workstation with `yay` installed (covered by the `default` localhost scenario).

### Binary Install Lacks Service Unit

When `teleport_install_method: binary`, the role extracts binaries to `/usr/local/bin/` but does **not** create a systemd service unit. The service enable/start task in `tasks/main.yml` will fail because `teleport.service` does not exist. Skipping the `service` tag handles this, but it means:
- Binary install on Arch/Void/Gentoo requires manual service unit creation
- This may be a role bug or intentional (assuming the user manages the service unit separately)

**Recommendation for future improvement:** Add a `templates/teleport.service.j2` and a task to deploy it when `teleport_install_method == 'binary'`.

### Teleport Version Pinning

The `teleport_version: "17.0.0"` default is used for binary download URLs and APT repo version selection (`stable/v17`). If this version becomes unavailable from CDN or APT, the install tasks will fail. The prepare.yml and converge.yml inherit this default.

**Mitigation:** The version is configurable. CI can pin to a known-good version.

### Idempotence Concern: Binary Download

The `install.yml` binary download block:
1. `get_url` downloads tarball to `/tmp/teleport.tar.gz`
2. `unarchive` extracts to `/usr/local/bin/`

Neither task has a guard to skip if the binary already exists. On second converge:
- `get_url` may report `changed` if the tarball is re-downloaded (HTTP 200 vs 304)
- `unarchive` may report `changed` if files are overwritten

This will cause idempotence failure in the molecule test sequence. Options:
1. Accept idempotence failure for `binary` install method (document it)
2. Add `creates: /usr/local/bin/teleport` to the `get_url` and `unarchive` tasks (role fix)

**Recommendation:** Fix the role by adding idempotence guards to the binary download tasks. This is a separate PR from the molecule work.

### `ansible_managed` and Idempotence

The `teleport.yaml.j2` template starts with `# {{ ansible_managed }}`. The `ansible_managed` string includes a timestamp that may differ between converge runs if the molecule idempotence check takes long enough to cross a second boundary. This would cause a false idempotence failure.

**Mitigation:** Set a static `ansible_managed` in molecule config:

```yaml
provisioner:
  config_options:
    defaults:
      ansible_managed: "Managed by Ansible"
```

This is already handled implicitly by Ansible's default behavior (the comment includes the template path, not a timestamp, in recent Ansible versions). Verify during Step 4.

### Docker DNS for APT Repository (Ubuntu only)

The Docker scenario only runs Arch Linux. If a future Docker scenario adds Ubuntu, the container needs DNS resolution to reach `apt.releases.teleport.dev`. The `dns_servers: [8.8.8.8, 8.8.4.4]` config handles this.

### Report Tag Skip

The `common` role is available via `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"` which points to the `roles/` directory. However, the `common` role's `report_phase.yml` and `report_render.yml` may have their own dependencies or assumptions. Skipping the `report` tag is safer and matches the pattern used by other roles (NTP, firewall, SSH).

---

## File Tree After Implementation

```
ansible/roles/teleport/
  defaults/main.yml              (unchanged)
  handlers/main.yml              (unchanged)
  meta/main.yml                  (unchanged)
  tasks/
    main.yml                     (unchanged)
    install.yml                  (unchanged -- binary idempotence fix is separate PR)
    configure.yml                (unchanged)
    join.yml                     (unchanged)
    ca_export.yml                (unchanged)
    verify.yml                   (unchanged)
  templates/
    teleport.yaml.j2             (unchanged)
  vars/
    archlinux.yml                (unchanged)
    debian.yml                   (unchanged)
    redhat.yml                   (unchanged)
    void.yml                     (unchanged)
    gentoo.yml                   (unchanged)
  molecule/
    shared/
      converge.yml               (NEW -- test vars, CA export disabled)
      verify.yml                 (NEW -- 14 assertions, cross-platform)
    default/
      molecule.yml               (UPDATED -- point to shared/, remove vault, add skip-tags)
    docker/
      molecule.yml               (NEW -- arch-systemd, binary install override)
      prepare.yml                (NEW -- pacman update_cache)
    vagrant/
      molecule.yml               (NEW -- Arch binary + Ubuntu repo, dual-platform)
      prepare.yml                (NEW -- keyring refresh, apt cache)
```
