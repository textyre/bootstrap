# vaultwarden: Molecule testing -- shared/docker/vagrant scenarios

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/vaultwarden/`

---

## 1. Current State

### What the role does

The `vaultwarden` role deploys a self-hosted Bitwarden-compatible password manager via Docker Compose behind a Caddy reverse proxy. It performs the following:

1. **Directories** -- Creates base directory (`/opt/vaultwarden`), data directory (mode `0700`), and backup directory.
2. **DNS** -- Adds `127.0.0.1 <domain>` to `/etc/hosts` for local resolution.
3. **Admin token** -- Generates a random admin token via `openssl rand -base64 48`, stores it in `.admin_token` (mode `0600`), reads it back via `slurp`, and sets it as a fact.
4. **Docker Compose** -- Deploys `docker-compose.yml` from template (Vaultwarden container on the `proxy` network).
5. **Caddy site config** -- Deploys `vault.caddy` reverse proxy config to `<caddy_base_dir>/sites/`.
6. **Container start** -- Starts Vaultwarden via `community.docker.docker_compose_v2`.
7. **Backup** -- Deploys a SQLite backup script (`backup.sh`, mode `0700`), enables `cronie` service, and configures a cron job.

### Role dependencies (meta/main.yml)

```yaml
dependencies:
  - role: docker
  - role: caddy
```

The `caddy` role itself depends on `docker`. So the full chain is: **docker -> caddy -> vaultwarden**.

### Variables (defaults/main.yml)

| Variable | Default | Purpose |
|----------|---------|---------|
| `vaultwarden_enabled` | `true` | Master toggle |
| `vaultwarden_domain` | `"vault.local"` | Domain for Caddy + DOMAIN env var |
| `vaultwarden_base_dir` | `"/opt/vaultwarden"` | Base directory on host |
| `vaultwarden_docker_network` | `"proxy"` | Docker network name |
| `vaultwarden_admin_enabled` | `true` | Enable /admin panel |
| `vaultwarden_admin_token` | `"{{ vault_vaultwarden_admin_token \| default('') }}"` | Admin token (vault-sourced) |
| `vaultwarden_signups_allowed` | `true` | Allow user registration |
| `vaultwarden_password_iterations` | `600000` | PBKDF2 iterations |
| `vaultwarden_login_ratelimit_max_burst` | `5` | Login burst limit |
| `vaultwarden_login_ratelimit_seconds` | `60` | Login rate window |
| `vaultwarden_admin_ratelimit_max_burst` | `3` | Admin burst limit |
| `vaultwarden_admin_ratelimit_seconds` | `60` | Admin rate window |
| `vaultwarden_backup_enabled` | `true` | Enable backup cron |
| `vaultwarden_backup_dir` | `"/opt/vaultwarden/backups"` | Backup destination |
| `vaultwarden_backup_keep_days` | `30` | Backup retention days |
| `vaultwarden_backup_cron_hour` | `"3"` | Cron hour |
| `vaultwarden_backup_cron_minute` | `"0"` | Cron minute |

### Templates

- **`docker-compose.yml.j2`** -- Vaultwarden container with env vars for domain, signups, admin token, rate limits. Volume mounts `data/`. Joins external `proxy` network.
- **`vault.caddy.j2`** -- Caddy site block with security headers (HSTS, nosniff, SAMEORIGIN, strict referrer) and `reverse_proxy vaultwarden:80`. TLS mode conditional on `caddy_tls_mode`.
- **`vaultwarden-backup.sh.j2`** -- Bash script using `sqlite3 .backup` for safe SQLite backup, tar for attachments, `find -mtime -delete` for rotation.

### Handlers

- **Restart vaultwarden** -- `docker compose -f <base_dir>/docker-compose.yml restart` (uses `listen:` directive).
- **Reload caddy** -- `docker exec caddy caddy reload --config /etc/caddy/Caddyfile` (uses `listen:` directive).

### What tests exist now

Single `molecule/default/` scenario:

- **Driver:** `default` (localhost, managed: false)
- **Provisioner:** Ansible with `vault_password_file` pointing to `vault-pass.sh`, local connection
- **converge.yml:** Loads vault.yml, applies `vaultwarden` role. No OS assertion.
- **verify.yml:** Loads vault.yml, runs 7 checks:
  1. Base directory exists
  2. Data directory exists with mode `0700`
  3. `docker-compose.yml` exists
  4. Caddy site config exists at `<caddy_base_dir>/sites/vault.caddy`
  5. Backup script exists and is executable
  6. Cron job contains "Vaultwarden backup" string
  7. Debug summary message

**Test sequence:** syntax, converge, idempotence, verify (no create/destroy -- localhost).

### Bugs found during analysis

**BUG-01: `_vaultwarden_token_file` undefined variable reference**
- Line 53 registers `vaultwarden_token_file` (no underscore prefix)
- Line 61 references `_vaultwarden_token_file.stat.exists` (with underscore prefix)
- This means the condition always evaluates to `not (false)` = `true`, so the token gets regenerated on every run that does not find the file. However, `creates:` parameter on the `shell` module provides a backup guard.
- Should be fixed as part of this work: either rename the register to `_vaultwarden_token_file` or change the reference to `vaultwarden_token_file`.

### Gaps in current tests

- No containerized testing (Docker scenario)
- No multi-platform testing (Vagrant scenario)
- No verification of `/etc/hosts` entry
- No verification of docker-compose.yml content (DOMAIN, environment vars)
- No verification of Caddy config content (security headers, reverse_proxy)
- No verification of backup script content
- No verification of admin token file existence and permissions
- No verification of directory ownership (root:root)
- Vault dependency in converge/verify makes it impossible to run in CI without vault secrets
- Uses `assert: os_family == Archlinux` pattern indirectly via dependency chain (docker/caddy are Arch-only)

---

## 2. Cross-Platform Analysis

### Arch Linux (primary target)

The role is Docker-based, so the host OS involvement is minimal:
- **Package dependencies:** `docker`, `docker-compose` (via docker role), `cronie` (for backup cron), `openssl` (for token generation), `sqlite3` (in backup script -- runs on HOST, not in container)
- **Service:** `cronie.service` (Arch-specific name; Debian uses `cron`)
- **Caddy site config path:** determined by `caddy_base_dir` (default `/opt/caddy/sites/`)

### Ubuntu/Debian (potential)

- **Package names differ:** `cron` instead of `cronie`, `sqlite3` same name
- **Service name differs:** `cron.service` instead of `cronie.service`
- **docker + caddy roles:** Currently Arch-only in their `meta/main.yml` platforms declaration

### Cross-platform blockers

| Component | Arch | Ubuntu/Debian | Status |
|-----------|------|---------------|--------|
| Docker install | `community.general.pacman` | Not implemented | BLOCKER |
| Caddy role | Arch-only | Not implemented | BLOCKER |
| Cronie service | `cronie` | `cron` | Hardcoded in tasks/main.yml line 135 |
| `openssl` | Pre-installed | Pre-installed | OK |
| `sqlite3` | Available | Available | OK (but backup script runs on host) |
| `/etc/hosts` | Standard | Standard | OK |
| Docker Compose | Via docker role | Via docker role | BLOCKER (docker role) |

**Conclusion:** Multi-distro Vagrant testing for vaultwarden is blocked by the dependency chain. Both `docker` and `caddy` roles are Arch-only. The Vagrant scenario should test **Arch only** until dependency roles are ported. Ubuntu can be added as a future item.

---

## 3. Shared Migration

### Current files to move

```
molecule/default/converge.yml  -->  molecule/shared/converge.yml
molecule/default/verify.yml    -->  molecule/shared/verify.yml
```

### Changes required for shared/converge.yml

The current converge.yml loads `vault.yml` and applies the role. For the shared version:

1. **Remove `vars_files` for vault.yml** -- The admin token is auto-generated by the role via `openssl rand`. The vault reference (`vault_vaultwarden_admin_token`) has a `default('')` fallback, so it works without vault.
2. **Keep role invocation simple** -- No OS assertion needed (the dependency chain handles Arch-only).
3. **Add skip-tags for Docker-incompatible tasks** -- The role calls `community.docker.docker_compose_v2` and `docker compose restart` in handlers. In Docker-in-Docker scenarios, these will fail. Tag the compose-start and handler tasks with a skip tag (e.g., `molecule-notest`) or use a prepare playbook to mock Docker.

**However**, this role is fundamentally a Docker Compose deployment. The core action IS starting Docker containers. This creates a testing challenge:

**Option A: Test only file deployment (skip Docker operations)**
- Skip tags: `service` or custom `molecule-notest` on `docker_compose_v2` task and `cronie` service task
- Verify: directories, files, templates content, permissions
- Pro: Works in systemd container without Docker-in-Docker
- Con: Does not test the actual deployment

**Option B: Docker-in-Docker (DinD)**
- Install Docker daemon inside the systemd container
- Pull vaultwarden image during prepare
- Pro: Tests full deployment
- Con: Heavy, slow, requires DinD-capable host, image pull in CI

**Recommendation: Option A for Docker scenario, Option B for Vagrant scenario.** The Docker scenario tests configuration correctness (templates, permissions, file content). The Vagrant scenario tests the full stack including container start.

### shared/converge.yml (proposed)

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  pre_tasks:
    - name: Set empty vault token (no vault needed in molecule)
      ansible.builtin.set_fact:
        vault_vaultwarden_admin_token: "molecule-test-token-not-for-production"

  roles:
    - role: vaultwarden
```

### shared/verify.yml (proposed)

See section 6 for full design.

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

The default scenario retains the vault_password_file for localhost runs where vault secrets are available. The shared converge sets a fallback token so it also works without vault.

---

## 4. Docker Scenario

### Challenges

This role has a deep dependency chain: **docker role -> caddy role -> vaultwarden role**. Each dependency performs significant work:

- **docker role:** Installs Docker daemon, configures `daemon.json`, starts `docker.service`. Inside a Docker container, we already have Docker concepts but not a nested Docker daemon.
- **caddy role:** Creates a Docker network (`proxy`), deploys Caddy via `docker_compose_v2`, starts Caddy container. Requires a running Docker daemon.

Running Docker-in-Docker in a systemd container is possible but adds significant complexity. For the Docker scenario, we should **mock the dependency outputs** and test only vaultwarden's own tasks with Docker operations skipped.

### Strategy: Stub dependencies + skip Docker tasks

1. **prepare.yml** installs prerequisites that the docker and caddy roles would normally provide (directories, packages).
2. **converge.yml** (shared) applies the vaultwarden role with `skip-tags: molecule-notest`.
3. Tasks that require a running Docker daemon get tagged `molecule-notest` in the role.

### Tasks requiring Docker daemon (to be tagged `molecule-notest`)

| Task | Line | Why |
|------|------|-----|
| `Start Vaultwarden containers` (docker_compose_v2) | 114-119 | Needs Docker daemon + image pull |
| `Ensure cronie service is enabled` | 133-138 | `cronie` not installed in container image |

Handlers also need Docker but only fire on notify, so they will not execute if the compose template is not changed after converge. No tagging needed for handlers in molecule since they are triggered by notify only.

### Tags that need adding to role tasks/main.yml

The `community.docker.docker_compose_v2` task at line 114 and the `cronie` service task at line 133 should receive an additional tag `molecule-notest` so the Docker scenario can skip them.

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
    skip-tags: molecule-notest
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

The prepare playbook must create the environment that docker and caddy roles would normally set up, so vaultwarden's tasks can run without those roles:

```yaml
---
- name: Prepare (stub docker + caddy dependencies)
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Update pacman cache
      community.general.pacman:
        update_cache: true

    - name: Install openssl (needed for admin token generation)
      community.general.pacman:
        name: openssl
        state: present

    - name: Install cronie (needed for backup cron)
      community.general.pacman:
        name: cronie
        state: present

    - name: Create Caddy directories (stub for caddy role)
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - /opt/caddy
        - /opt/caddy/sites
```

### What the Docker scenario tests

- Directory creation: base, data (0700), backup
- `/etc/hosts` entry for `vault.local`
- Admin token generation: `.admin_token` file exists, mode `0600`
- Template deployment: `docker-compose.yml`, `vault.caddy`, `backup.sh`
- Template content: environment variables, security headers, backup script correctness
- File permissions: all deployed files have correct owner/group/mode
- Cron job: "Vaultwarden backup" in `crontab -l` (requires cronie installed in prepare)
- Idempotence: second converge produces no changes

### What the Docker scenario does NOT test

- Actual Docker container start (skipped via `molecule-notest`)
- Docker network creation (caddy role responsibility)
- Caddy reload handler
- Vaultwarden restart handler
- Actual HTTPS connectivity

---

## 5. Vagrant Scenario

### Scope

The Vagrant scenario tests the full deployment including Docker daemon, container start, and network connectivity. **Arch Linux only** (Ubuntu blocked by dependency chain -- see section 2).

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

The Vagrant prepare must install Docker and set up the environment that the dependency roles expect. Since meta dependencies (`docker` and `caddy`) will be resolved automatically by Ansible when the role is applied, we need to ensure the VM has the packages available:

```yaml
---
- name: Prepare Vagrant VM
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Update pacman cache
      community.general.pacman:
        update_cache: true

    - name: Install Docker prerequisites
      community.general.pacman:
        name:
          - docker
          - docker-compose
          - openssl
          - cronie
          - sqlite3
        state: present

    - name: Enable and start Docker service
      ansible.builtin.service:
        name: docker
        enabled: true
        state: started

    - name: Wait for Docker daemon to be ready
      ansible.builtin.command:
        cmd: docker info
      register: _prepare_docker_info
      retries: 10
      delay: 3
      until: _prepare_docker_info.rc == 0
      changed_when: false

    - name: Create Docker proxy network
      community.docker.docker_network:
        name: proxy
        state: present
```

**Note:** The dependency roles (docker, caddy) will run as part of converge because they are in `meta/main.yml`. The prepare just ensures the base packages are present so the roles can configure them. The docker role will configure `daemon.json` and the caddy role will deploy its containers.

### What the Vagrant scenario tests (beyond Docker scenario)

- Full dependency chain execution (docker -> caddy -> vaultwarden)
- Docker daemon configuration via docker role
- Caddy container deployment
- Vaultwarden container deployment via `docker_compose_v2`
- Docker `proxy` network connectivity
- `cronie.service` running
- Container health (vaultwarden running)
- End-to-end: curl `https://vault.local` returns a response (via Caddy reverse proxy)

### Vagrant idempotence consideration

The `community.docker.docker_compose_v2` module and `openssl rand` token generation may cause idempotence issues:
- Token generation: The `creates:` parameter on the shell task should prevent re-runs. However, BUG-01 (undefined `_vaultwarden_token_file`) means the `when:` condition always passes. The `creates:` guard should still prevent actual re-execution.
- Docker compose: The `state: present` should be idempotent if the compose file has not changed.
- Caddy CA trust tasks: `docker cp` and `update-ca-trust` use `changed_when: true`, which will always report changed. These are caddy role tasks and may need `molecule-notest` tagging in that role separately.

---

## 6. Verify.yml Design

### Philosophy

Use `ansible.builtin.assert` with descriptive `fail_msg` (following the ntp reference pattern). Load defaults via `vars_files` so variable references work. Separate checks into logical sections with comment headers.

### shared/verify.yml

```yaml
---
- name: Verify vaultwarden role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- Directories ----

    - name: Stat base directory
      ansible.builtin.stat:
        path: "{{ vaultwarden_base_dir }}"
      register: _vw_verify_base_dir

    - name: Assert base directory exists with correct ownership
      ansible.builtin.assert:
        that:
          - _vw_verify_base_dir.stat.exists
          - _vw_verify_base_dir.stat.isdir
          - _vw_verify_base_dir.stat.pw_name == 'root'
          - _vw_verify_base_dir.stat.gr_name == 'root'
          - _vw_verify_base_dir.stat.mode == '0755'
        fail_msg: >-
          {{ vaultwarden_base_dir }} missing or wrong permissions
          (expected root:root 0755)

    - name: Stat data directory
      ansible.builtin.stat:
        path: "{{ vaultwarden_base_dir }}/data"
      register: _vw_verify_data_dir

    - name: Assert data directory exists with mode 0700
      ansible.builtin.assert:
        that:
          - _vw_verify_data_dir.stat.exists
          - _vw_verify_data_dir.stat.isdir
          - _vw_verify_data_dir.stat.pw_name == 'root'
          - _vw_verify_data_dir.stat.gr_name == 'root'
          - _vw_verify_data_dir.stat.mode == '0700'
        fail_msg: >-
          {{ vaultwarden_base_dir }}/data missing or wrong permissions
          (expected root:root 0700)

    - name: Stat backup directory
      ansible.builtin.stat:
        path: "{{ vaultwarden_backup_dir }}"
      register: _vw_verify_backup_dir

    - name: Assert backup directory exists
      ansible.builtin.assert:
        that:
          - _vw_verify_backup_dir.stat.exists
          - _vw_verify_backup_dir.stat.isdir
          - _vw_verify_backup_dir.stat.mode == '0755'
        fail_msg: >-
          {{ vaultwarden_backup_dir }} missing or wrong permissions
          (expected 0755)

    # ---- DNS ----

    - name: Read /etc/hosts
      ansible.builtin.slurp:
        src: /etc/hosts
      register: _vw_verify_hosts_raw

    - name: Assert domain is in /etc/hosts
      ansible.builtin.assert:
        that:
          - "vaultwarden_domain in (_vw_verify_hosts_raw.content | b64decode)"
        fail_msg: >-
          {{ vaultwarden_domain }} not found in /etc/hosts

    # ---- Admin token ----

    - name: Stat admin token file
      ansible.builtin.stat:
        path: "{{ vaultwarden_base_dir }}/.admin_token"
      register: _vw_verify_token

    - name: Assert admin token file exists with correct permissions
      ansible.builtin.assert:
        that:
          - _vw_verify_token.stat.exists
          - _vw_verify_token.stat.isreg
          - _vw_verify_token.stat.pw_name == 'root'
          - _vw_verify_token.stat.gr_name == 'root'
          - _vw_verify_token.stat.mode == '0600'
        fail_msg: >-
          {{ vaultwarden_base_dir }}/.admin_token missing or wrong
          permissions (expected root:root 0600)
      when: vaultwarden_admin_enabled

    - name: Read admin token file
      ansible.builtin.slurp:
        src: "{{ vaultwarden_base_dir }}/.admin_token"
      register: _vw_verify_token_content
      when: vaultwarden_admin_enabled

    - name: Assert admin token is non-empty
      ansible.builtin.assert:
        that:
          - (_vw_verify_token_content.content | b64decode | trim) | length > 0
        fail_msg: "Admin token file is empty"
      when: vaultwarden_admin_enabled

    # ---- Docker Compose file ----

    - name: Stat docker-compose.yml
      ansible.builtin.stat:
        path: "{{ vaultwarden_base_dir }}/docker-compose.yml"
      register: _vw_verify_compose

    - name: Assert docker-compose.yml exists
      ansible.builtin.assert:
        that:
          - _vw_verify_compose.stat.exists
          - _vw_verify_compose.stat.isreg
          - _vw_verify_compose.stat.mode == '0644'
        fail_msg: >-
          {{ vaultwarden_base_dir }}/docker-compose.yml missing or
          wrong permissions (expected 0644)

    - name: Read docker-compose.yml
      ansible.builtin.slurp:
        src: "{{ vaultwarden_base_dir }}/docker-compose.yml"
      register: _vw_verify_compose_raw

    - name: Set compose text fact
      ansible.builtin.set_fact:
        _vw_verify_compose_text: >-
          {{ _vw_verify_compose_raw.content | b64decode }}

    - name: Assert docker-compose.yml contains expected content
      ansible.builtin.assert:
        that:
          - "'vaultwarden/server:latest' in _vw_verify_compose_text"
          - "'DOMAIN' in _vw_verify_compose_text"
          - "vaultwarden_domain in _vw_verify_compose_text"
          - "'PASSWORD_ITERATIONS' in _vw_verify_compose_text"
          - "'proxy' in _vw_verify_compose_text"
        fail_msg: >-
          docker-compose.yml missing expected content (image, DOMAIN,
          PASSWORD_ITERATIONS, proxy network)

    # ---- Caddy site config ----

    - name: Stat Caddy site config
      ansible.builtin.stat:
        path: "{{ caddy_base_dir | default('/opt/caddy') }}/sites/vault.caddy"
      register: _vw_verify_caddy

    - name: Assert Caddy site config exists
      ansible.builtin.assert:
        that:
          - _vw_verify_caddy.stat.exists
          - _vw_verify_caddy.stat.isreg
          - _vw_verify_caddy.stat.mode == '0644'
        fail_msg: >-
          Caddy site config missing or wrong permissions (expected 0644)

    - name: Read Caddy site config
      ansible.builtin.slurp:
        src: "{{ caddy_base_dir | default('/opt/caddy') }}/sites/vault.caddy"
      register: _vw_verify_caddy_raw

    - name: Set caddy config text fact
      ansible.builtin.set_fact:
        _vw_verify_caddy_text: >-
          {{ _vw_verify_caddy_raw.content | b64decode }}

    - name: Assert Caddy config contains security headers and reverse proxy
      ansible.builtin.assert:
        that:
          - "vaultwarden_domain in _vw_verify_caddy_text"
          - "'Strict-Transport-Security' in _vw_verify_caddy_text"
          - "'X-Content-Type-Options' in _vw_verify_caddy_text"
          - "'X-Frame-Options' in _vw_verify_caddy_text"
          - "'reverse_proxy vaultwarden:80' in _vw_verify_caddy_text"
        fail_msg: >-
          Caddy site config missing expected content (domain, security
          headers, reverse_proxy directive)

    # ---- Backup script ----

    - name: Stat backup script
      ansible.builtin.stat:
        path: "{{ vaultwarden_base_dir }}/backup.sh"
      register: _vw_verify_backup_script

    - name: Assert backup script exists and is executable
      ansible.builtin.assert:
        that:
          - _vw_verify_backup_script.stat.exists
          - _vw_verify_backup_script.stat.isreg
          - _vw_verify_backup_script.stat.executable
          - _vw_verify_backup_script.stat.mode == '0700'
        fail_msg: >-
          {{ vaultwarden_base_dir }}/backup.sh missing or not
          executable (expected mode 0700)
      when: vaultwarden_backup_enabled

    - name: Read backup script
      ansible.builtin.slurp:
        src: "{{ vaultwarden_base_dir }}/backup.sh"
      register: _vw_verify_backup_raw
      when: vaultwarden_backup_enabled

    - name: Assert backup script contains expected content
      ansible.builtin.assert:
        that:
          - "'sqlite3' in (_vw_verify_backup_raw.content | b64decode)"
          - "'.backup' in (_vw_verify_backup_raw.content | b64decode)"
          - "'set -euo pipefail' in (_vw_verify_backup_raw.content | b64decode)"
        fail_msg: >-
          Backup script missing expected content (sqlite3, .backup,
          pipefail)
      when: vaultwarden_backup_enabled

    # ---- Cron job ----

    - name: Check crontab for backup job
      ansible.builtin.command:
        cmd: crontab -l
      register: _vw_verify_cron
      changed_when: false
      failed_when: false
      when: vaultwarden_backup_enabled

    - name: Assert backup cron job exists
      ansible.builtin.assert:
        that:
          - "'backup.sh' in _vw_verify_cron.stdout"
        fail_msg: >-
          Vaultwarden backup cron job not found in root crontab
      when: vaultwarden_backup_enabled

    # ---- Docker containers (Vagrant only) ----

    - name: Check vaultwarden container is running
      ansible.builtin.command:
        cmd: docker ps --filter name=vaultwarden --format '{%raw%}{{.Status}}{%endraw%}'
      register: _vw_verify_container
      changed_when: false
      failed_when: false
      when: ansible_facts['virtualization_type'] | default('') != 'docker'

    - name: Assert vaultwarden container is running
      ansible.builtin.assert:
        that:
          - "'Up' in _vw_verify_container.stdout"
        fail_msg: >-
          Vaultwarden container is not running. Output:
          {{ _vw_verify_container.stdout | default('empty') }}
      when:
        - ansible_facts['virtualization_type'] | default('') != 'docker'
        - _vw_verify_container is defined

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Vaultwarden verify passed: directories exist (base 0755,
          data 0700, backup 0755), domain in /etc/hosts, admin token
          generated (0600), docker-compose.yml deployed with correct
          content, Caddy site config has security headers, backup
          script executable, cron job configured.
```

### Key design decisions

1. **`vars_files: ../../defaults/main.yml`** -- Loads role defaults so all `vaultwarden_*` variables are available without re-declaring them. This follows the project pattern from molecule testing notes.

2. **`_vw_verify_*` register prefix** -- Namespaced to avoid collisions. The `_vw_` prefix identifies vaultwarden verify variables.

3. **Docker container check gated by `virtualization_type != 'docker'`** -- In the Docker molecule scenario, we are inside a container and skip Docker-related checks. In Vagrant (KVM), we verify the container is actually running.

4. **Template content assertions** -- Going beyond "file exists" to verify key content elements (domain, security headers, reverse_proxy, sqlite3 backup command). This catches template rendering bugs.

5. **`failed_when: false` on crontab** -- Avoids hard failure if cronie is not installed (Docker scenario with skipped cronie task). The subsequent assert handles the actual verification.

---

## 7. Implementation Order

### Step 1: Fix BUG-01 (variable name mismatch)

**File:** `ansible/roles/vaultwarden/tasks/main.yml`

Change line 53 from:
```yaml
  register: vaultwarden_token_file
```
to:
```yaml
  register: _vaultwarden_token_file
```

This aligns the registered variable name with the reference on line 61.

### Step 2: Add `molecule-notest` tags to Docker-dependent tasks

**File:** `ansible/roles/vaultwarden/tasks/main.yml`

Add `molecule-notest` to the tags list for:
- Line 114-119: `Start Vaultwarden containers` task
- Line 133-138: `Ensure cronie service is enabled` task

Example:
```yaml
- name: Start Vaultwarden containers
  community.docker.docker_compose_v2:
    project_src: "{{ vaultwarden_base_dir }}"
    state: present
  when: vaultwarden_enabled
  tags: ['vaultwarden', 'secrets', 'molecule-notest']
```

### Step 3: Create `molecule/shared/` directory and files

1. Create `molecule/shared/converge.yml` (from section 3)
2. Create `molecule/shared/verify.yml` (from section 6)

### Step 4: Update `molecule/default/molecule.yml`

Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`. Remove local `converge.yml` and `verify.yml` from `molecule/default/`.

### Step 5: Create `molecule/docker/` scenario

1. Create `molecule/docker/molecule.yml` (from section 4)
2. Create `molecule/docker/prepare.yml` (from section 4)

### Step 6: Test Docker scenario

```bash
cd ansible/roles/vaultwarden
molecule test -s docker
```

Expected: syntax + create + prepare + converge + idempotence + verify + destroy all pass.

### Step 7: Create `molecule/vagrant/` scenario

1. Create `molecule/vagrant/molecule.yml` (from section 5)
2. Create `molecule/vagrant/prepare.yml` (from section 5)

### Step 8: Test Vagrant scenario

```bash
cd ansible/roles/vaultwarden
molecule test -s vagrant
```

Expected: Full stack test including Docker daemon, Caddy, and Vaultwarden container start.

### Step 9: Test default (localhost) scenario still works

```bash
cd ansible/roles/vaultwarden
molecule test
```

### Step 10: Delete old molecule/default/ playbook files

After confirming all scenarios work, remove the now-unused files:
- `molecule/default/converge.yml` (replaced by shared)
- `molecule/default/verify.yml` (replaced by shared)

---

## 8. Risks / Notes

### Risk: Docker image pull in CI

The converge pulls `vaultwarden/server:latest` via `docker_compose_v2`. In the Vagrant scenario, this requires internet access and may be slow (image is ~100MB+). Mitigation:
- Vagrant scenario is not expected to run in CI (too heavy)
- Docker scenario skips the container start entirely

### Risk: Idempotence failures

Several tasks may report `changed` on second run:
- **`openssl rand` token generation:** Guarded by `creates:` parameter -- should be idempotent. But BUG-01 means the `when:` condition passes every time. After fixing BUG-01, the `stat` check will also guard it.
- **Caddy role's `docker cp` and `update-ca-trust`:** These use `changed_when: true` and will always report changed. This is a caddy role issue, not vaultwarden's.
- **`docker_compose_v2 state: present`:** Should be idempotent if compose file unchanged.

### Risk: cronie availability in Docker container

The Arch systemd container image may not have `cronie` pre-installed. The prepare playbook installs it explicitly. If the image lacks `pacman` mirrors or network access, this will fail. Mitigation: the container uses `dns_servers: [8.8.8.8, 8.8.4.4]`.

### Risk: sqlite3 in backup script verification

The backup script references `sqlite3` which is a host-level binary. Verify checks script content (string match) but does not execute it. Execution testing would require an actual SQLite database file, which is only created by a running Vaultwarden container.

### Risk: caddy_base_dir dependency

The verify.yml uses `caddy_base_dir | default('/opt/caddy')` to locate the Caddy site config. If the caddy role changes its default, this fallback may diverge. Consider loading caddy defaults too, but this adds complexity. The `/opt/caddy` default is stable and documented.

### Note: vault.yml no longer required

The shared converge sets a test token via `set_fact`, and all vault-sourced variables have `default('')` fallbacks. The `molecule/default/` scenario retains `vault_password_file` for localhost runs where vault is available, but it is not required for Docker or Vagrant scenarios.

### Note: Ubuntu/multi-distro support deferred

Multi-distro testing is blocked by the docker and caddy roles being Arch-only. When those roles gain Debian/Ubuntu support, the vaultwarden role will need:
1. Conditional service name: `cronie` (Arch) vs `cron` (Debian)
2. Ubuntu platform added to Vagrant `molecule.yml`
3. Separate prepare tasks for apt-based package installation

### Final file tree after implementation

```
ansible/roles/vaultwarden/
  defaults/main.yml
  handlers/main.yml
  meta/main.yml
  tasks/main.yml                     (BUG-01 fixed, molecule-notest tags added)
  templates/
    docker-compose.yml.j2
    vault.caddy.j2
    vaultwarden-backup.sh.j2
  molecule/
    shared/
      converge.yml                   (NEW -- shared across all scenarios)
      verify.yml                     (NEW -- comprehensive assertions)
    default/
      molecule.yml                   (UPDATED -- points to shared playbooks)
    docker/
      molecule.yml                   (NEW -- Arch systemd container)
      prepare.yml                    (NEW -- stub dependencies)
    vagrant/
      molecule.yml                   (NEW -- full-stack KVM test)
      prepare.yml                    (NEW -- install Docker + prereqs)
```
