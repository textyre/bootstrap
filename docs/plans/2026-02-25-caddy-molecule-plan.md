# Caddy Role: Molecule Testing Plan

**Date:** 2026-02-25
**Status:** Draft
**Role:** `ansible/roles/caddy/`

---

## 1. Current State

### What the role does

The `caddy` role deploys Caddy as a Docker-based reverse proxy with automatic TLS:

1. **Docker network** -- creates the `proxy` network via `community.docker.docker_network`
2. **Directory structure** -- creates `caddy_base_dir` (`/opt/caddy/`) with subdirs: `sites/`, `data/`, `config/`
3. **Caddyfile** -- deploys `/opt/caddy/Caddyfile` from `Caddyfile.j2` (global options: `local_certs` when internal TLS, `admin off`, imports from `/etc/caddy/sites/*.caddy`)
4. **docker-compose.yml** -- deploys compose file using `caddy:2-alpine` image, maps ports 80/443, mounts volumes (Caddyfile, sites, data, config), connects to the `proxy` network
5. **Service start** -- runs `community.docker.docker_compose_v2` with `state: present`
6. **CA trust** (internal TLS only):
   - Copies Caddy root CA from container to `/etc/ca-certificates/trust-source/anchors/caddy-local.crt`
   - Runs `update-ca-trust`
   - Configures Zen Browser to import enterprise roots (with `failed_when: false`)
7. **Handlers** -- `Restart caddy` (docker compose restart) and `Reload caddy` (docker exec caddy reload)

**Dependencies:** Depends on `docker` role (`meta/main.yml: dependencies: [role: docker]`).

**Platform support declared:** ArchLinux only in `meta/main.yml`.

**Key variables** (`defaults/main.yml`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `caddy_enabled` | `true` | Master toggle |
| `caddy_base_dir` | `/opt/caddy` | Base directory for all Caddy files |
| `caddy_https_port` | `443` | HTTPS port mapping |
| `caddy_http_port` | `80` | HTTP port mapping |
| `caddy_tls_mode` | `"internal"` | TLS mode: `internal` (self-signed) or `acme` |
| `caddy_tls_email` | `""` | ACME email (Let's Encrypt) |
| `caddy_docker_network` | `"proxy"` | Docker network name |

### Existing tests

Single `molecule/default/` scenario:

```
molecule/default/
  molecule.yml    -- default driver (localhost), vault, local connection
  converge.yml    -- loads vault.yml, applies caddy role
  verify.yml      -- 4 stat checks: base dir, Caddyfile, docker-compose.yml, sites dir
```

**Test sequence:** syntax, converge, idempotence, verify (no create/destroy since localhost).

**Gaps in current tests:**
- No Docker or Vagrant scenarios
- No cross-platform testing (Arch-only)
- Verify only checks file existence -- no content validation, no permissions check, no service assertions
- No validation of Caddyfile content (`local_certs`, `admin off`, `import` directive)
- No validation of docker-compose.yml content (image, ports, volumes, networks)
- No Docker network existence check
- No Caddy container running check
- No `caddy validate` syntax check
- Vault dependency in converge (role has no vault variables -- the dependency is unnecessary)
- Hardcoded paths (`/opt/caddy`) instead of using variables from `defaults/main.yml`

---

## 2. Cross-Platform Analysis

### Architecture: Docker-based (not native package)

Unlike most roles that install native packages, the caddy role runs Caddy inside a Docker container via docker-compose. This means:
- The `caddy` binary is **not** installed on the host
- The Caddy process runs inside the `caddy:2-alpine` container
- Configuration files live on the host filesystem and are bind-mounted into the container
- Service management is via `docker compose` commands, not systemd

This architecture is inherently cross-platform: any OS that runs Docker can run this role.

### Platform differences

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| Docker package | `docker` (pacman) | `docker.io` (apt) or `docker-ce` (official repo) |
| Docker compose | Built into docker CLI (v2) | Built into docker CLI (v2) |
| CA trust store path | `/etc/ca-certificates/trust-source/anchors/` | `/usr/local/share/ca-certificates/` |
| CA trust update cmd | `update-ca-trust` | `update-ca-certificates` |
| Zen Browser | AUR package (may exist) | Not available |
| `community.docker` collection | Required on controller | Required on controller |

### Cross-platform blockers in current code

1. **CA trust path is Arch-specific** -- `/etc/ca-certificates/trust-source/anchors/` is an Arch Linux path. Ubuntu uses `/usr/local/share/ca-certificates/`. The `docker cp` and `file` tasks on lines 66-78 would fail on Ubuntu.
2. **`update-ca-trust` is Arch-specific** -- Ubuntu uses `update-ca-certificates`.
3. **Zen Browser path** -- `/usr/lib/zen-browser/distribution` is Arch-specific (already has `failed_when: false`).

### Impact on testing

For cross-platform Vagrant testing, the verify.yml needs to either:
- Skip CA trust assertions on Ubuntu (since the tasks would fail during converge), OR
- The role should be updated with distro-conditional CA trust tasks before cross-platform testing

**Decision for this plan:** The verify.yml will test the core functionality (directories, config files, Docker network, container state) which is cross-platform. CA trust assertions will be gated on `ansible_facts['os_family'] == 'Archlinux'`. The Vagrant scenario will include Ubuntu for smoke-testing the Docker-based deployment path, with `failed_when: false` on Arch-specific CA trust tasks handled by the role itself (already present for Zen Browser, needs to be added for CA trust tasks).

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
    - role: caddy
```

Changes from current `default/converge.yml`:
- **Removed** `vars_files` vault reference (role has no vault variables)

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
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"

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
- **Changed** playbook paths to `../shared/`
- Vault password file retained (default scenario runs on localhost where vault may be needed by docker dependency)

---

## 4. Docker Scenario

### The fundamental challenge: Docker-in-Docker

The caddy role requires a **running Docker daemon** to:
1. Create Docker networks (`community.docker.docker_network`)
2. Deploy and start containers (`community.docker.docker_compose_v2`)
3. Execute commands inside containers (`docker exec`, `docker cp`)

This is a Docker-in-Docker (DinD) scenario. Running a Docker daemon inside a molecule Docker container is possible but fragile. The same challenge exists for the docker role (see `2026-02-25-docker-role-molecule-plan.md` Section 4).

### Recommended approach: Config-only verification

In the Docker scenario, **skip Docker daemon-dependent tasks** and verify only the configuration artifacts:
- Directory structure created
- Caddyfile content correct
- docker-compose.yml content correct
- File permissions correct

Tasks that require a running Docker daemon (network creation, compose up, docker cp, docker exec) are skipped via tags.

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
    skip-tags: service,proxy
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      Archlinux-systemd:
        docker_enable_service: false
        caddy_enabled: true
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

**Key decisions:**
- `skip-tags: service,proxy` -- skips Docker service start (from docker role dependency) and could be used for Caddy service tasks. However, the caddy role's tasks use tags `caddy`, `proxy`, `configure`, `service`. We need the `configure` tags to run (directory creation, file templating) but skip `service` (compose up) and any Docker-daemon-dependent tasks.
- `docker_enable_service: false` -- prevents the docker dependency role from trying to start dockerd
- The `caddy` role's tasks are guarded by `when: caddy_enabled` and tagged. The tasks that need Docker daemon are:
  - `Create Docker network for proxy` (tagged `caddy, proxy, configure`) -- uses `community.docker.docker_network` which requires dockerd
  - `Start Caddy with docker compose` (tagged `caddy, proxy, service`) -- uses `community.docker.docker_compose_v2`
  - `Copy Caddy root CA` (tagged `caddy, proxy, configure`) -- uses `docker cp`
  - `Update system CA trust` (tagged `caddy, proxy, configure`) -- runs `update-ca-trust`

**Problem:** The `configure` tag covers both file-only tasks (directory creation, template deployment) AND Docker-dependent tasks (network creation, CA copy). We cannot selectively skip by tag alone.

**Revised approach:** Use `skip-tags: service` to skip compose-up, and accept that some tasks will fail in the Docker container. The prepare.yml can install a mock or we handle this with a converge override.

**Better approach:** Since the Docker scenario cannot meaningfully test Docker-dependent tasks, create a `molecule/docker/converge.yml` that applies the role with limited scope instead of using the shared converge:

### molecule/docker/converge.yml (scenario-specific)

```yaml
---
- name: Converge (config-only)
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Include caddy defaults
      ansible.builtin.include_vars:
        file: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/defaults/main.yml"

    - name: Create Caddy directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - "{{ caddy_base_dir }}"
        - "{{ caddy_base_dir }}/sites"
        - "{{ caddy_base_dir }}/data"
        - "{{ caddy_base_dir }}/config"

    - name: Deploy Caddyfile
      ansible.builtin.template:
        src: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/templates/Caddyfile.j2"
        dest: "{{ caddy_base_dir }}/Caddyfile"
        owner: root
        group: root
        mode: '0644'

    - name: Deploy docker-compose.yml
      ansible.builtin.template:
        src: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/templates/docker-compose.yml.j2"
        dest: "{{ caddy_base_dir }}/docker-compose.yml"
        owner: root
        group: root
        mode: '0644'
```

**Wait -- this breaks the "shared converge" pattern.** Let me reconsider.

### Final approach for Docker scenario

Use the shared converge but accept partial failures. The molecule Docker scenario tests what it can:

1. Update `molecule/docker/molecule.yml` to use `../shared/converge.yml`
2. Add `ignore_errors: true` handling -- **No, this is not how molecule works.**

**Actual final approach:** The caddy role's tasks all have `when: caddy_enabled`. Set `caddy_enabled: false` in host_vars to skip ALL caddy tasks during converge, then use a separate prepare.yml that manually creates the config files. This defeats the purpose.

**Pragmatic decision:** For the caddy role, the Docker molecule scenario has limited value because the role is fundamentally Docker-dependent. The most practical approach:

1. **Docker scenario**: Run converge with `--skip-tags service` and accept that Docker-daemon-dependent tasks will fail. Use `failed_when: false` on those tasks (requires role modification) OR use a custom converge that only exercises the config-only subset.
2. **Vagrant scenario**: Full test with real Docker daemon.

Since modifying the role to add `failed_when: false` would change production behavior, the Docker scenario will use a **custom converge** that exercises only the file-deployment tasks. The shared converge is used by default and vagrant scenarios.

### Revised molecule/docker/molecule.yml

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
    converge: converge.yml
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

### molecule/docker/converge.yml (config-only)

```yaml
---
- name: Converge (config-only -- no Docker daemon available)
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/defaults/main.yml"

  tasks:

    # ---- Directory structure ----

    - name: Create Caddy directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - "{{ caddy_base_dir }}"
        - "{{ caddy_base_dir }}/sites"
        - "{{ caddy_base_dir }}/data"
        - "{{ caddy_base_dir }}/config"

    # ---- Configuration files ----

    - name: Deploy Caddyfile
      ansible.builtin.template:
        src: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/templates/Caddyfile.j2"
        dest: "{{ caddy_base_dir }}/Caddyfile"
        owner: root
        group: root
        mode: '0644'

    - name: Deploy docker-compose.yml
      ansible.builtin.template:
        src: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/templates/docker-compose.yml.j2"
        dest: "{{ caddy_base_dir }}/docker-compose.yml"
        owner: root
        group: root
        mode: '0644'
```

This converge replays the file-deployment subset of the role without requiring Docker daemon. It uses `vars_files` to load role defaults so paths are variable-driven.

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

### Docker scenario scope

| What is tested | Yes/No |
|----------------|--------|
| Directory structure creation | Yes |
| Caddyfile template rendering | Yes |
| docker-compose.yml template rendering | Yes |
| File permissions (owner, group, mode) | Yes |
| Caddyfile content (local_certs, admin off, import) | Yes |
| docker-compose.yml content (image, ports, volumes, networks) | Yes |
| Docker network creation | No (requires dockerd) |
| Caddy container running | No (requires dockerd) |
| caddy validate | No (requires running container) |
| CA trust deployment | No (requires docker cp from running container) |
| Idempotence of file tasks | Yes |

---

## 5. Vagrant Scenario

### Why Vagrant

Vagrant VMs provide a real environment with:
- Docker daemon running natively
- `docker compose` fully functional
- Container networking (ports 80/443 bound on VM, not conflicting with host)
- Full CA trust chain testing possible
- `caddy validate` inside running container

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

    # ---- Arch Linux ----

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

    - name: Install Docker on Arch (prerequisite for caddy role)
      community.general.pacman:
        name:
          - docker
          - docker-compose
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Enable and start Docker on Arch
      ansible.builtin.service:
        name: docker
        enabled: true
        state: started
      when: ansible_facts['os_family'] == 'Archlinux'

    # ---- Ubuntu / Debian ----

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Install Docker on Ubuntu (docker.io from universe)
      ansible.builtin.apt:
        name:
          - docker.io
          - docker-compose-v2
          - python3
          - python3-docker
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    - name: Enable and start Docker on Ubuntu
      ansible.builtin.service:
        name: docker
        enabled: true
        state: started
      when: ansible_facts['os_family'] == 'Debian'
```

**Key points:**
- Docker must be installed and running BEFORE the caddy role converge, since the caddy role's `meta/main.yml` declares `dependencies: [role: docker]`. However, the docker dependency role only *configures* Docker (daemon.json, user group, service), it does not *install* it. Package installation is done in prepare.yml.
- `docker-compose` (v2 plugin) is needed for `community.docker.docker_compose_v2` module.
- `python3-docker` is needed on Ubuntu for `community.docker` Ansible modules (provides the Python `docker` SDK).

### Cross-platform notes for Vagrant

| Task in caddy role | Arch | Ubuntu |
|-------------------|------|--------|
| Create Docker network | Works | Works |
| Create directories | Works | Works |
| Deploy Caddyfile | Works | Works |
| Deploy docker-compose.yml | Works | Works |
| docker compose up | Works | Works |
| docker cp CA cert | Works | **Path wrong**: `/etc/ca-certificates/trust-source/anchors/` does not exist on Ubuntu |
| Fix CA permissions | Works | **Path wrong** |
| update-ca-trust | Works | **Command wrong**: Ubuntu uses `update-ca-certificates` |
| Zen Browser policies | Fails silently (`failed_when: false`) | Fails silently |

**Ubuntu will fail on CA trust tasks.** The caddy role hardcodes Arch-specific paths and commands for CA trust. Since these tasks do NOT have `failed_when: false`, the converge will fail on Ubuntu when `caddy_tls_mode == "internal"`.

**Mitigation options:**
1. Set `caddy_tls_mode: "acme"` on Ubuntu to skip CA trust tasks (they are gated by `when: caddy_tls_mode == "internal"`)
2. Override `caddy_tls_mode` in vagrant molecule provisioner host_vars for Ubuntu

**Chosen approach:** Set `caddy_tls_mode: "acme"` for the Ubuntu VM and `caddy_tls_email: "test@example.com"` (ACME mode requires an email, but Caddy will not actually request a cert without a real domain). Alternatively, disable the caddy_enabled flag on Ubuntu -- but this defeats the purpose of cross-platform testing.

**Better approach:** Set `caddy_tls_mode: "acme"` on Ubuntu to bypass all CA trust tasks. Caddy will start, but ACME cert issuance will fail (no real domain). The container will still be running and serving HTTP on port 80. The verify.yml can check the container is running and Caddyfile is deployed, without asserting HTTPS functionality.

Update `molecule/vagrant/molecule.yml` provisioner section:

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
    host_vars:
      ubuntu-noble:
        caddy_tls_mode: "acme"
        caddy_tls_email: "test@example.com"
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
```

---

## 6. Verify.yml Design

### molecule/shared/verify.yml

```yaml
---
- name: Verify caddy role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ===========================================================
    # Directory structure
    # ===========================================================

    - name: Stat caddy base directory
      ansible.builtin.stat:
        path: "{{ caddy_base_dir }}"
      register: caddy_verify_base_dir

    - name: Assert caddy base directory exists with correct permissions
      ansible.builtin.assert:
        that:
          - caddy_verify_base_dir.stat.exists
          - caddy_verify_base_dir.stat.isdir
          - caddy_verify_base_dir.stat.pw_name == 'root'
          - caddy_verify_base_dir.stat.gr_name == 'root'
          - caddy_verify_base_dir.stat.mode == '0755'
        fail_msg: >-
          {{ caddy_base_dir }} missing or wrong permissions
          (expected root:root 0755)

    - name: Stat caddy subdirectories
      ansible.builtin.stat:
        path: "{{ caddy_base_dir }}/{{ item }}"
      loop:
        - sites
        - data
        - config
      register: caddy_verify_subdirs

    - name: Assert caddy subdirectories exist
      ansible.builtin.assert:
        that:
          - item.stat.exists
          - item.stat.isdir
        fail_msg: "{{ item.item }} directory missing under {{ caddy_base_dir }}"
      loop: "{{ caddy_verify_subdirs.results }}"
      loop_control:
        label: "{{ item.item }}"

    # ===========================================================
    # Caddyfile -- existence and permissions
    # ===========================================================

    - name: Stat Caddyfile
      ansible.builtin.stat:
        path: "{{ caddy_base_dir }}/Caddyfile"
      register: caddy_verify_caddyfile

    - name: Assert Caddyfile exists with correct permissions
      ansible.builtin.assert:
        that:
          - caddy_verify_caddyfile.stat.exists
          - caddy_verify_caddyfile.stat.isreg
          - caddy_verify_caddyfile.stat.pw_name == 'root'
          - caddy_verify_caddyfile.stat.gr_name == 'root'
          - caddy_verify_caddyfile.stat.mode == '0644'
        fail_msg: >-
          {{ caddy_base_dir }}/Caddyfile missing or wrong permissions
          (expected root:root 0644)

    # ===========================================================
    # Caddyfile -- content assertions
    # ===========================================================

    - name: Read Caddyfile
      ansible.builtin.slurp:
        src: "{{ caddy_base_dir }}/Caddyfile"
      register: caddy_verify_caddyfile_raw

    - name: Set Caddyfile text fact
      ansible.builtin.set_fact:
        caddy_verify_caddyfile_text: "{{ caddy_verify_caddyfile_raw.content | b64decode }}"

    - name: Assert Caddyfile contains Ansible managed marker
      ansible.builtin.assert:
        that: "'Ansible' in caddy_verify_caddyfile_text"
        fail_msg: "Ansible managed marker not found in Caddyfile"

    - name: Assert Caddyfile contains admin off directive
      ansible.builtin.assert:
        that: "'admin off' in caddy_verify_caddyfile_text"
        fail_msg: "'admin off' directive missing from Caddyfile"

    - name: Assert Caddyfile contains local_certs (internal TLS mode)
      ansible.builtin.assert:
        that: "'local_certs' in caddy_verify_caddyfile_text"
        fail_msg: "'local_certs' directive missing from Caddyfile (expected for tls_mode=internal)"
      when: caddy_tls_mode == "internal"

    - name: Assert Caddyfile does NOT contain local_certs (ACME TLS mode)
      ansible.builtin.assert:
        that: "'local_certs' not in caddy_verify_caddyfile_text"
        fail_msg: "'local_certs' directive found in Caddyfile but tls_mode is 'acme'"
      when: caddy_tls_mode == "acme"

    - name: Assert Caddyfile imports sites directory
      ansible.builtin.assert:
        that: "'import /etc/caddy/sites/*.caddy' in caddy_verify_caddyfile_text"
        fail_msg: "'import /etc/caddy/sites/*.caddy' directive missing from Caddyfile"

    # ===========================================================
    # docker-compose.yml -- existence and permissions
    # ===========================================================

    - name: Stat docker-compose.yml
      ansible.builtin.stat:
        path: "{{ caddy_base_dir }}/docker-compose.yml"
      register: caddy_verify_compose

    - name: Assert docker-compose.yml exists with correct permissions
      ansible.builtin.assert:
        that:
          - caddy_verify_compose.stat.exists
          - caddy_verify_compose.stat.isreg
          - caddy_verify_compose.stat.pw_name == 'root'
          - caddy_verify_compose.stat.gr_name == 'root'
          - caddy_verify_compose.stat.mode == '0644'
        fail_msg: >-
          {{ caddy_base_dir }}/docker-compose.yml missing or wrong permissions
          (expected root:root 0644)

    # ===========================================================
    # docker-compose.yml -- content assertions
    # ===========================================================

    - name: Read docker-compose.yml
      ansible.builtin.slurp:
        src: "{{ caddy_base_dir }}/docker-compose.yml"
      register: caddy_verify_compose_raw

    - name: Set docker-compose.yml text fact
      ansible.builtin.set_fact:
        caddy_verify_compose_text: "{{ caddy_verify_compose_raw.content | b64decode }}"

    - name: Assert docker-compose.yml contains Ansible managed marker
      ansible.builtin.assert:
        that: "'Ansible' in caddy_verify_compose_text"
        fail_msg: "Ansible managed marker not found in docker-compose.yml"

    - name: Assert docker-compose.yml uses caddy:2-alpine image
      ansible.builtin.assert:
        that: "'caddy:2-alpine' in caddy_verify_compose_text"
        fail_msg: "caddy:2-alpine image not found in docker-compose.yml"

    - name: Assert docker-compose.yml maps HTTPS port
      ansible.builtin.assert:
        that: "'{{ caddy_https_port | string }}:443' in caddy_verify_compose_text"
        fail_msg: "HTTPS port mapping {{ caddy_https_port }}:443 not found in docker-compose.yml"

    - name: Assert docker-compose.yml maps HTTP port
      ansible.builtin.assert:
        that: "'{{ caddy_http_port | string }}:80' in caddy_verify_compose_text"
        fail_msg: "HTTP port mapping {{ caddy_http_port }}:80 not found in docker-compose.yml"

    - name: Assert docker-compose.yml mounts Caddyfile
      ansible.builtin.assert:
        that: "'{{ caddy_base_dir }}/Caddyfile:/etc/caddy/Caddyfile:ro' in caddy_verify_compose_text"
        fail_msg: "Caddyfile volume mount not found in docker-compose.yml"

    - name: Assert docker-compose.yml mounts sites directory
      ansible.builtin.assert:
        that: "'{{ caddy_base_dir }}/sites:/etc/caddy/sites:ro' in caddy_verify_compose_text"
        fail_msg: "Sites volume mount not found in docker-compose.yml"

    - name: Assert docker-compose.yml references proxy network
      ansible.builtin.assert:
        that: "'{{ caddy_docker_network }}' in caddy_verify_compose_text"
        fail_msg: "Docker network '{{ caddy_docker_network }}' not found in docker-compose.yml"

    # ===========================================================
    # Docker network (requires Docker daemon -- Vagrant/localhost only)
    # ===========================================================

    - name: Check Docker daemon is running  # noqa: command-instead-of-module
      ansible.builtin.command: docker info
      register: caddy_verify_docker_info
      changed_when: false
      failed_when: false

    - name: Docker network and container assertions
      when: caddy_verify_docker_info.rc == 0
      block:

        - name: Check proxy Docker network exists  # noqa: command-instead-of-module
          ansible.builtin.command: docker network inspect {{ caddy_docker_network }}
          register: caddy_verify_network
          changed_when: false
          failed_when: false

        - name: Assert proxy Docker network exists
          ansible.builtin.assert:
            that: caddy_verify_network.rc == 0
            fail_msg: >-
              Docker network '{{ caddy_docker_network }}' does not exist.
              Expected the caddy role to create it.

        # ===========================================================
        # Caddy container state (requires Docker daemon)
        # ===========================================================

        - name: Check caddy container is running  # noqa: command-instead-of-module
          ansible.builtin.command: docker inspect --format '{{ '{{' }}.State.Status{{ '}}' }}' caddy
          register: caddy_verify_container_status
          changed_when: false
          failed_when: false

        - name: Assert caddy container is running
          ansible.builtin.assert:
            that:
              - caddy_verify_container_status.rc == 0
              - caddy_verify_container_status.stdout == 'running'
            fail_msg: >-
              Caddy container is not running.
              Status: {{ caddy_verify_container_status.stdout | default('container not found') }}

        # ===========================================================
        # Caddy config validation (requires running container)
        # ===========================================================

        - name: Validate Caddyfile syntax inside container  # noqa: command-instead-of-module
          ansible.builtin.command: docker exec caddy caddy validate --config /etc/caddy/Caddyfile
          register: caddy_verify_validate
          changed_when: false
          failed_when: false

        - name: Assert Caddyfile validation passed
          ansible.builtin.assert:
            that: caddy_verify_validate.rc == 0
            fail_msg: >-
              Caddyfile validation failed inside container:
              {{ caddy_verify_validate.stderr | default('') }}

        # ===========================================================
        # Caddy container network connectivity
        # ===========================================================

        - name: Check caddy container is connected to proxy network  # noqa: command-instead-of-module
          ansible.builtin.command: >
            docker inspect --format '{{ '{{' }}json .NetworkSettings.Networks{{ '}}' }}' caddy
          register: caddy_verify_container_networks
          changed_when: false
          failed_when: false

        - name: Assert caddy container is connected to proxy network
          ansible.builtin.assert:
            that: "'{{ caddy_docker_network }}' in caddy_verify_container_networks.stdout"
            fail_msg: >-
              Caddy container is not connected to '{{ caddy_docker_network }}' network.
              Networks: {{ caddy_verify_container_networks.stdout | default('') }}

    - name: Warn if Docker daemon not available (config-only verification)
      ansible.builtin.debug:
        msg: >-
          Docker daemon not available (rc={{ caddy_verify_docker_info.rc }}).
          Skipping Docker network, container, and caddy validate checks.
          This is expected in molecule Docker (container) scenarios.
      when: caddy_verify_docker_info.rc != 0

    # ===========================================================
    # CA trust (Arch Linux + internal TLS only, requires Docker daemon)
    # ===========================================================

    - name: Verify CA trust deployment
      when:
        - caddy_tls_mode == "internal"
        - caddy_verify_docker_info.rc == 0
        - ansible_facts['os_family'] == 'Archlinux'
      block:

        - name: Stat Caddy root CA in system trust store
          ansible.builtin.stat:
            path: /etc/ca-certificates/trust-source/anchors/caddy-local.crt
          register: caddy_verify_ca_cert

        - name: Assert Caddy root CA exists in trust store
          ansible.builtin.assert:
            that:
              - caddy_verify_ca_cert.stat.exists
              - caddy_verify_ca_cert.stat.mode == '0644'
            fail_msg: >-
              Caddy root CA not found at
              /etc/ca-certificates/trust-source/anchors/caddy-local.crt
              or has wrong permissions

    # ===========================================================
    # Summary
    # ===========================================================

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Caddy role verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}.
          Docker checks: {{ 'enabled' if caddy_verify_docker_info.rc == 0 else 'skipped (no daemon)' }}.
          CA trust checks: {{ 'enabled' if (caddy_tls_mode == 'internal' and
          caddy_verify_docker_info.rc == 0 and
          ansible_facts['os_family'] == 'Archlinux') else 'skipped' }}.
```

### Assertion summary table

| # | Assertion | Docker scenario | Vagrant (Arch) | Vagrant (Ubuntu) |
|---|-----------|----------------|----------------|-----------------|
| 1 | Base directory exists, root:root 0755 | Yes | Yes | Yes |
| 2 | Subdirectories (sites, data, config) exist | Yes | Yes | Yes |
| 3 | Caddyfile exists, root:root 0644 | Yes | Yes | Yes |
| 4 | Caddyfile: Ansible managed marker | Yes | Yes | Yes |
| 5 | Caddyfile: `admin off` directive | Yes | Yes | Yes |
| 6 | Caddyfile: `local_certs` (internal mode) | Yes | Yes | Skipped (acme mode) |
| 7 | Caddyfile: no `local_certs` (acme mode) | Skipped | Skipped | Yes |
| 8 | Caddyfile: `import /etc/caddy/sites/*.caddy` | Yes | Yes | Yes |
| 9 | docker-compose.yml exists, root:root 0644 | Yes | Yes | Yes |
| 10 | docker-compose.yml: Ansible managed marker | Yes | Yes | Yes |
| 11 | docker-compose.yml: `caddy:2-alpine` image | Yes | Yes | Yes |
| 12 | docker-compose.yml: HTTPS port mapping | Yes | Yes | Yes |
| 13 | docker-compose.yml: HTTP port mapping | Yes | Yes | Yes |
| 14 | docker-compose.yml: Caddyfile mount | Yes | Yes | Yes |
| 15 | docker-compose.yml: sites mount | Yes | Yes | Yes |
| 16 | docker-compose.yml: proxy network reference | Yes | Yes | Yes |
| 17 | Docker network exists | Skipped | Yes | Yes |
| 18 | Caddy container running | Skipped | Yes | Yes |
| 19 | `caddy validate` passes | Skipped | Yes | Yes |
| 20 | Caddy container on proxy network | Skipped | Yes | Yes |
| 21 | CA root cert in trust store | Skipped | Yes | Skipped (acme mode) |

---

## 7. Implementation Order

### Step 1: Create shared directory and playbooks

```
mkdir -p ansible/roles/caddy/molecule/shared/
```

Create `molecule/shared/converge.yml` (simplified, no vault).
Create `molecule/shared/verify.yml` (comprehensive, from Section 6).

### Step 2: Update molecule/default/molecule.yml

- Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
- Keep vault password file (default runs on localhost)

### Step 3: Delete old converge.yml and verify.yml from default/

```
rm ansible/roles/caddy/molecule/default/converge.yml
rm ansible/roles/caddy/molecule/default/verify.yml
```

### Step 4: Create Docker scenario

```
mkdir -p ansible/roles/caddy/molecule/docker/
```

Create:
- `molecule/docker/molecule.yml` -- Arch systemd container
- `molecule/docker/converge.yml` -- config-only (no Docker daemon tasks)
- `molecule/docker/prepare.yml` -- pacman update_cache

### Step 5: Create Vagrant scenario

```
mkdir -p ansible/roles/caddy/molecule/vagrant/
```

Create:
- `molecule/vagrant/molecule.yml` -- Arch + Ubuntu VMs, Ubuntu host_vars override
- `molecule/vagrant/prepare.yml` -- cross-platform Docker installation

### Step 6: Test locally

```bash
# Default scenario (localhost)
cd ansible && molecule test -s default -- --tags caddy

# Docker scenario (config-only)
cd ansible/roles/caddy && molecule test -s docker

# Vagrant scenario (full, requires libvirt)
cd ansible/roles/caddy && molecule test -s vagrant
```

### Step 7: Verify idempotence

- Docker scenario: file-only tasks should be idempotent (template module compares content)
- Vagrant scenario: all tasks should be idempotent EXCEPT:
  - `docker cp caddy:/data/caddy/...` has `changed_when: true` -- will always report changed
  - `update-ca-trust` has `changed_when: true` -- will always report changed

**Idempotence risk:** The CA trust tasks (lines 66-85 in `tasks/main.yml`) use `changed_when: true` which means the idempotence check WILL FAIL on Vagrant (Arch). Options:
1. Accept idempotence failure and document it
2. Remove idempotence from Vagrant test sequence
3. Fix the role to be idempotent (use `creates:` parameter or `stat` check)

**Recommendation:** Remove `idempotence` from Vagrant test_sequence for now. The CA trust tasks are inherently non-idempotent as written (using `ansible.builtin.command` with `changed_when: true`). The Docker scenario (config-only) should pass idempotence.

### Step 8: Commit

```
feat(caddy): add molecule docker + vagrant scenarios with shared verify
```

---

## 8. Risks / Notes

### Docker-in-Docker limitations

The caddy role is fundamentally Docker-dependent. The molecule Docker scenario can only test configuration file artifacts, not the actual Docker network/container/service behavior. Full integration testing requires Vagrant or a real host.

### Port 80/443 conflicts

In Vagrant VMs, ports 80 and 443 are bound inside the VM, not on the host. No port conflict with the developer's machine. In Docker containers (if we were to run the full role), port binding would conflict with the host. This is moot since the Docker scenario is config-only.

### TLS in test environment

- **Internal TLS mode** (default): Caddy generates a self-signed CA and issues certs automatically. No external dependencies. Works in Vagrant VMs.
- **ACME mode**: Requires a real domain pointing to the VM and ports 80/443 publicly accessible. Not feasible in test environments. Used only as a workaround for Ubuntu (to skip CA trust tasks).

### Caddyfile validation

The `caddy validate` command runs inside the running Caddy container. It validates the Caddyfile syntax, not the TLS certificate chain. This assertion is only meaningful when the container is running (Vagrant scenario).

### community.docker collection dependency

The caddy role uses:
- `community.docker.docker_network` -- requires `docker` Python SDK on the managed node
- `community.docker.docker_compose_v2` -- requires `docker compose` CLI on the managed node

The Vagrant prepare.yml must install both the Docker daemon AND the Python Docker SDK (`python3-docker` on Ubuntu, included with `docker` package on Arch).

### Caddy container image pull

The converge will pull `caddy:2-alpine` from Docker Hub. This requires internet access in the VM and is subject to Docker Hub rate limits. In CI environments with limited internet or behind a proxy, this could fail.

**Mitigation:** The Vagrant VMs have DNS and internet access by default. For CI behind a proxy, configure `docker_daemon_config` with registry mirrors.

### CA trust tasks are Arch-only

The current role hardcodes Arch Linux paths for CA trust (`/etc/ca-certificates/trust-source/anchors/`, `update-ca-trust`). Ubuntu testing uses `caddy_tls_mode: "acme"` to bypass these tasks entirely. A future enhancement should add distro-conditional CA trust tasks to the role itself.

### Idempotence of command tasks

Three tasks in the caddy role use `ansible.builtin.command` with `changed_when: true`:
- `docker cp caddy:/data/caddy/pki/...` (line 67)
- `update-ca-trust` (line 83)
- Handler: `docker compose restart` (handler)

These will always report "changed" on every run, breaking idempotence checks. This is a pre-existing role issue, not introduced by the molecule plan. The Vagrant scenario should exclude `idempotence` from the test sequence, or these tasks should be refactored with proper `changed_when` logic.

### meta/main.yml update consideration

The current `meta/main.yml` lists only ArchLinux and declares `dependencies: [role: docker]`. For full cross-platform support:
1. Add Ubuntu/Debian to platforms
2. The docker dependency role would also need cross-platform support

For this testing plan, the Vagrant scenario tests Ubuntu without modifying `meta/main.yml`. The role tasks that are distro-agnostic (directories, templates, compose) work on Ubuntu. The docker dependency is handled by prepare.yml installing Docker before converge.

---

## File tree after implementation

```
ansible/roles/caddy/
  defaults/main.yml                (unchanged)
  handlers/main.yml                (unchanged)
  meta/main.yml                    (unchanged)
  tasks/main.yml                   (unchanged)
  templates/
    Caddyfile.j2                   (unchanged)
    docker-compose.yml.j2          (unchanged)
  molecule/
    shared/
      converge.yml                 (NEW -- simplified, no vault)
      verify.yml                   (NEW -- 21 assertions, cross-platform guards)
    default/
      molecule.yml                 (UPDATED -- point to shared/)
      converge.yml                 (DELETED)
      verify.yml                   (DELETED)
    docker/
      molecule.yml                 (NEW -- arch-systemd container, config-only)
      converge.yml                 (NEW -- config-only subset, no Docker daemon tasks)
      prepare.yml                  (NEW -- pacman update_cache)
    vagrant/
      molecule.yml                 (NEW -- Arch + Ubuntu VMs, Ubuntu host_vars override)
      prepare.yml                  (NEW -- cross-platform Docker install + start)
```
