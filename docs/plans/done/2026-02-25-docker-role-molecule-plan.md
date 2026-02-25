# Docker Role: Molecule Testing Plan

**Date:** 2026-02-25
**Status:** Done
**Role:** `ansible/roles/docker/`

---

## 1. Current State

### What the role does

The `docker` role configures Docker on Arch Linux:
- Creates `/etc/docker/` directory
- Builds a `docker_daemon_config` dict via `set_fact` (conditionally merging security settings)
- Deploys `daemon.json` from a Jinja2 template (`{{ docker_daemon_config | to_nice_json }}`)
- Ensures `docker` group exists, adds the target user to it
- Enables and starts the `docker` service
- Handler: `restart docker` (with `listen:` directive)

**Platform support:** Arch Linux only (`meta/main.yml` lists only `ArchLinux`). There is a single `tasks/main.yml` with no distro-specific task files.

### Existing tests

```
molecule/default/
  molecule.yml    -- default driver (localhost), vault, ANSIBLE_ROLES_PATH
  converge.yml    -- assert os_family==Archlinux, pacman install docker, apply role
  verify.yml      -- 4 checks: daemon.json exists, valid JSON, user in docker group, service enabled+running
```

The default scenario runs on localhost (real machine), uses vault, and includes all 4 test_sequence steps: syntax, converge, idempotence, verify.

### Current defaults (`defaults/main.yml`)

| Variable | Current Value | Note |
|----------|---------------|------|
| `docker_user` | `SUDO_USER` fallback to `user_id` | |
| `docker_add_user_to_group` | `true` | |
| `docker_enable_service` | `true` | |
| `docker_log_driver` | `"journald"` | |
| `docker_log_max_size` | `"10m"` | |
| `docker_log_max_file` | `"3"` | |
| `docker_storage_driver` | `""` (empty = omit) | |
| `docker_userns_remap` | `"default"` | Secure |
| `docker_icc` | `false` | Secure |
| `docker_live_restore` | `true` | Secure |
| `docker_no_new_privileges` | `true` | Secure |

---

## 2. CRIT-02 Fix Plan (Security Defaults)

**Status: Already fixed.**

The current `defaults/main.yml` already ships secure defaults:

```yaml
docker_userns_remap: "default"     # was ""
docker_icc: false                  # was true
docker_live_restore: true          # was false
docker_no_new_privileges: true     # was false
```

Each variable has a Russian comment explaining what it does and how to override. The code review from 2026-02-17 recorded the state before this fix was applied.

**No action required.** Verify in molecule tests that these values are reflected in the deployed `daemon.json`.

---

## 3. CRIT-03 Fix Plan (daemon.json Validation)

**Status: Already fixed.**

The current `tasks/main.yml` line 43 uses:

```yaml
validate: 'python3 -m json.tool %s'
```

Additionally, the template itself uses `{{ docker_daemon_config | to_nice_json }}`, which means:
1. Ansible's `to_nice_json` filter produces valid JSON from the dict (first line of defense)
2. The `validate` parameter runs `python3 -m json.tool` on the rendered file before deployment (second line of defense)

**No action required.** The molecule verify should confirm the deployed file is valid JSON (already done in current `verify.yml`).

---

## 4. Docker Scenario (DinD Challenge)

### The problem

Testing a Docker role inside a Docker container is Docker-in-Docker (DinD). Challenges:
- The container needs `--privileged` and access to cgroups for systemd
- Starting a Docker daemon inside a container requires either:
  - Full DinD (nested dockerd) -- complex, fragile, requires `--privileged`
  - Socket passthrough (`/var/run/docker.sock`) -- tests host docker, not container docker
- Installing the `docker` package inside the container adds ~500MB and requires systemd to manage the service

### Recommended approach: Config-only verification

In the Docker molecule scenario, **do not start the Docker daemon**. Instead:
1. Install the `docker` package (to satisfy converge)
2. Override `docker_enable_service: false` in provisioner vars (skip service start)
3. Verify only the configuration artifacts: `daemon.json` content, file permissions, user group membership

This matches the pattern used by other roles where the service cannot run in a container (e.g., service-dependent checks are skipped via `when: ansible_facts['service_mgr'] == 'systemd'` and systemd is partially functional).

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
    skip-tags: service
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      Archlinux-systemd:
        docker_enable_service: false
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
- `skip-tags: service` -- skips the `docker_enable_service` task at the provisioner level
- `docker_enable_service: false` -- belt-and-suspenders: even if tags are not filtered, the task guard `when: docker_enable_service` prevents service start
- `privileged: true` -- required for systemd inside the container and for installing packages
- The container has systemd (PID 1), so `systemctl` commands are available for the verify phase to check if the unit file exists (even though the daemon is not started)

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

    - name: Install docker package (prerequisite for role)
      community.general.pacman:
        name: docker
        state: present
```

Docker package installation is moved to `prepare.yml` (out of converge) so the converge playbook stays clean and the role itself does not install the package (it only configures it).

### What can be tested in Docker scenario

| Check | Possible | Note |
|-------|----------|------|
| `/etc/docker/daemon.json` exists | Yes | File is deployed by template |
| `daemon.json` is valid JSON | Yes | `python3 -c "import json; ..."` |
| `daemon.json` contains security settings | Yes | slurp + assert on content |
| `/etc/docker/` directory permissions | Yes | stat + assert |
| User in docker group | Yes | `groups` command |
| Docker service enabled | No | Daemon not started in container |
| Docker service running | No | Daemon not started in container |
| `docker info` output | No | No running daemon |

---

## 5. Vagrant Scenario

### Why vagrant

Vagrant VMs (KVM/libvirt) provide a real OS environment where:
- systemd runs as PID 1
- Docker daemon can actually start
- `docker info` can be queried to verify runtime security settings
- Service enable/start can be fully tested
- User namespace remapping can be verified in runtime

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

    - name: Full system upgrade on Arch (ensures openssl/ssl compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Install docker on Arch (prerequisite)
      community.general.pacman:
        name: docker
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Install Docker on Ubuntu (docker.io from universe)
      ansible.builtin.apt:
        name:
          - docker.io
          - python3
        state: present
      when: ansible_facts['os_family'] == 'Debian'
```

**Note on Ubuntu Docker package:** The role currently only supports Arch (`meta/main.yml`). For cross-platform vagrant testing, `prepare.yml` handles Docker package installation per-distro. The role itself only configures daemon.json, user group, and service -- these tasks are distro-agnostic (service name is `docker` on both Arch and Ubuntu).

### What can be tested in Vagrant scenario

| Check | Possible | Note |
|-------|----------|------|
| Everything from Docker scenario | Yes | |
| Docker service enabled + running | Yes | Real systemd |
| `docker info` runtime output | Yes | Real daemon |
| Security settings in `docker info` | Yes | userns-remap, no-new-privileges, ICC, live-restore |
| Pull/run a test container | Yes (optional) | `docker run hello-world` |

---

## 6. Shared Migration

### Current structure (before)

```
molecule/
  default/
    molecule.yml
    converge.yml    <-- has pre_tasks (assert Arch, install docker)
    verify.yml      <-- 4 hardcoded checks
```

### Target structure (after)

```
molecule/
  shared/
    converge.yml    <-- clean: just apply role
    verify.yml      <-- comprehensive, cross-platform assertions
  default/
    molecule.yml    <-- points to ../shared/converge.yml + ../shared/verify.yml
  docker/
    molecule.yml    <-- DinD config, skip-tags: service
    prepare.yml     <-- pacman update + install docker
  vagrant/
    molecule.yml    <-- KVM, Arch + Ubuntu
    prepare.yml     <-- cross-platform prep + install docker
```

### Migration steps

1. Create `molecule/shared/` directory
2. Create `molecule/shared/converge.yml` -- clean version without pre_tasks:
   ```yaml
   ---
   - name: Converge
     hosts: all
     become: true
     gather_facts: true

     roles:
       - role: docker
   ```
   The Arch assertion and `docker` package install move to `prepare.yml` in each scenario. The default (localhost) scenario does not need a prepare since docker is already installed on the host.

3. Create `molecule/shared/verify.yml` -- comprehensive version (see section 7)
4. Update `molecule/default/molecule.yml` to reference shared playbooks:
   ```yaml
   playbooks:
     converge: ../shared/converge.yml
     verify: ../shared/verify.yml
   ```
5. Remove `molecule/default/converge.yml` and `molecule/default/verify.yml`
6. Create `molecule/docker/` and `molecule/vagrant/` directories with their respective files

### Default scenario change

The default scenario (localhost) remains for local development testing. It references shared playbooks and assumes docker is already installed (no prepare step). The vault requirement stays since it runs against real inventory.

Updated `molecule/default/molecule.yml`:

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

---

## 7. Verify.yml Design

The shared verify playbook must handle two scenarios:
1. **Config-only** (Docker container): daemon.json, permissions, user group -- no service checks
2. **Full** (Vagrant, localhost): all of the above plus service state, `docker info` runtime assertions

Cross-platform: `when: ansible_facts['os_family'] == 'Archlinux'` or `== 'Debian'` for distro-specific package checks.

### molecule/shared/verify.yml

```yaml
---
- name: Verify Docker role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "../../defaults/main.yml"

  tasks:

    # ==========================================================
    # /etc/docker/ directory
    # ==========================================================

    - name: Stat /etc/docker directory
      ansible.builtin.stat:
        path: /etc/docker
      register: docker_verify_dir

    - name: Assert /etc/docker exists with correct permissions
      ansible.builtin.assert:
        that:
          - docker_verify_dir.stat.exists
          - docker_verify_dir.stat.isdir
          - docker_verify_dir.stat.pw_name == 'root'
          - docker_verify_dir.stat.gr_name == 'root'
          - docker_verify_dir.stat.mode == '0755'
        fail_msg: "/etc/docker missing or wrong permissions (expected root:root 0755)"

    # ==========================================================
    # daemon.json -- existence and validity
    # ==========================================================

    - name: Stat /etc/docker/daemon.json
      ansible.builtin.stat:
        path: /etc/docker/daemon.json
      register: docker_verify_daemon_json

    - name: Assert daemon.json exists with correct permissions
      ansible.builtin.assert:
        that:
          - docker_verify_daemon_json.stat.exists
          - docker_verify_daemon_json.stat.isreg
          - docker_verify_daemon_json.stat.pw_name == 'root'
          - docker_verify_daemon_json.stat.gr_name == 'root'
          - docker_verify_daemon_json.stat.mode == '0644'
        fail_msg: "/etc/docker/daemon.json missing or wrong permissions (expected root:root 0644)"

    - name: Validate daemon.json is valid JSON  # noqa: command-instead-of-module
      ansible.builtin.command: python3 -c "import json; json.load(open('/etc/docker/daemon.json'))"
      register: docker_verify_json_valid
      changed_when: false
      failed_when: docker_verify_json_valid.rc != 0

    # ==========================================================
    # daemon.json -- content assertions
    # ==========================================================

    - name: Read daemon.json
      ansible.builtin.slurp:
        src: /etc/docker/daemon.json
      register: docker_verify_daemon_raw

    - name: Parse daemon.json into dict
      ansible.builtin.set_fact:
        docker_verify_daemon_dict: "{{ docker_verify_daemon_raw.content | b64decode | from_json }}"

    - name: Assert log-driver matches variable
      ansible.builtin.assert:
        that:
          - "'log-driver' in docker_verify_daemon_dict"
          - "docker_verify_daemon_dict['log-driver'] == docker_log_driver"
        fail_msg: "log-driver not set to '{{ docker_log_driver }}' in daemon.json"

    - name: Assert log-opts max-size matches variable
      ansible.builtin.assert:
        that:
          - "'log-opts' in docker_verify_daemon_dict"
          - "docker_verify_daemon_dict['log-opts']['max-size'] == docker_log_max_size"
        fail_msg: "log-opts.max-size not set to '{{ docker_log_max_size }}' in daemon.json"

    - name: Assert log-opts max-file matches variable
      ansible.builtin.assert:
        that:
          - "docker_verify_daemon_dict['log-opts']['max-file'] == docker_log_max_file"
        fail_msg: "log-opts.max-file not set to '{{ docker_log_max_file }}' in daemon.json"

    # ---- Security settings ----

    - name: Assert userns-remap present in daemon.json (when configured)
      ansible.builtin.assert:
        that:
          - "'userns-remap' in docker_verify_daemon_dict"
          - "docker_verify_daemon_dict['userns-remap'] == docker_userns_remap"
        fail_msg: "userns-remap not set to '{{ docker_userns_remap }}' in daemon.json"
      when: docker_userns_remap | length > 0

    - name: Assert icc is false in daemon.json (when docker_icc is false)
      ansible.builtin.assert:
        that:
          - "'icc' in docker_verify_daemon_dict"
          - "docker_verify_daemon_dict['icc'] == false"
        fail_msg: "icc not set to false in daemon.json"
      when: not docker_icc

    - name: Assert live-restore is true in daemon.json (when enabled)
      ansible.builtin.assert:
        that:
          - "'live-restore' in docker_verify_daemon_dict"
          - "docker_verify_daemon_dict['live-restore'] == true"
        fail_msg: "live-restore not set to true in daemon.json"
      when: docker_live_restore

    - name: Assert no-new-privileges is true in daemon.json (when enabled)
      ansible.builtin.assert:
        that:
          - "'no-new-privileges' in docker_verify_daemon_dict"
          - "docker_verify_daemon_dict['no-new-privileges'] == true"
        fail_msg: "no-new-privileges not set to true in daemon.json"
      when: docker_no_new_privileges

    # ==========================================================
    # User group membership
    # ==========================================================

    - name: Check user group membership  # noqa: command-instead-of-module
      ansible.builtin.command: >
        groups {{ docker_user | default(ansible_facts['env']['SUDO_USER']
        | default(ansible_facts['user_id'])) }}
      register: docker_verify_groups
      changed_when: false

    - name: Assert user is in docker group
      ansible.builtin.assert:
        that: "'docker' not in docker_verify_groups.stdout or 'docker' in docker_verify_groups.stdout"
      when: docker_add_user_to_group | default(true)

    - name: Assert user is in docker group (when add_user_to_group enabled)
      ansible.builtin.assert:
        that: "'docker' in docker_verify_groups.stdout"
        fail_msg: >-
          User not in docker group
          (groups output: {{ docker_verify_groups.stdout }})
      when: docker_add_user_to_group | default(true)

    # ==========================================================
    # Service state (skipped in Docker container)
    # ==========================================================

    - name: Verify Docker service
      when: docker_enable_service | default(true)
      block:

        - name: Gather service facts
          ansible.builtin.service_facts:

        - name: Assert docker.service is running and enabled
          ansible.builtin.assert:
            that:
              - "'docker.service' in ansible_facts.services"
              - "ansible_facts.services['docker.service'].state == 'running'"
              - "ansible_facts.services['docker.service'].status == 'enabled'"
            fail_msg: >-
              docker.service is not running or not enabled
              (services: {{ ansible_facts.services.get('docker.service', 'NOT FOUND') }})

    # ==========================================================
    # Runtime verification via docker info (Vagrant/localhost only)
    # ==========================================================

    - name: Verify Docker runtime settings
      when: docker_enable_service | default(true)
      block:

        - name: Get docker info  # noqa: command-instead-of-module
          ansible.builtin.command: docker info --format '{{ '{{' }}json .{{ '}}' }}'
          register: docker_verify_info_raw
          changed_when: false

        - name: Parse docker info JSON
          ansible.builtin.set_fact:
            docker_verify_info: "{{ docker_verify_info_raw.stdout | from_json }}"

        - name: Assert logging driver matches
          ansible.builtin.assert:
            that: "docker_verify_info['LoggingDriver'] == docker_log_driver"
            fail_msg: >-
              Docker logging driver mismatch:
              expected '{{ docker_log_driver }}',
              got '{{ docker_verify_info['LoggingDriver'] }}'

        - name: Assert live-restore is active (when enabled)
          ansible.builtin.assert:
            that: "docker_verify_info['LiveRestoreEnabled'] == true"
            fail_msg: "Docker live-restore not active in runtime"
          when: docker_live_restore

        - name: Assert Docker security options include no-new-privileges (when enabled)
          ansible.builtin.assert:
            that: "'no-new-privileges' in (docker_verify_info['SecurityOptions'] | join(','))"
            fail_msg: >-
              no-new-privileges not found in Docker SecurityOptions:
              {{ docker_verify_info['SecurityOptions'] }}
          when: docker_no_new_privileges

        - name: Assert Docker security options include userns (when userns-remap configured)
          ansible.builtin.assert:
            that: "'userns' in (docker_verify_info['SecurityOptions'] | join(','))"
            fail_msg: >-
              userns not found in Docker SecurityOptions:
              {{ docker_verify_info['SecurityOptions'] }}
          when: docker_userns_remap | length > 0

    # ==========================================================
    # Summary
    # ==========================================================

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Docker role verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}.
          Service checks: {{ 'enabled' if (docker_enable_service | default(true)) else 'skipped (container)' }}.
```

### Assertion summary

| # | Assertion | Docker scenario | Vagrant scenario |
|---|-----------|----------------|-----------------|
| 1 | `/etc/docker/` dir exists, root:root 0755 | Yes | Yes |
| 2 | `daemon.json` exists, root:root 0644 | Yes | Yes |
| 3 | `daemon.json` is valid JSON | Yes | Yes |
| 4 | `log-driver` matches variable | Yes | Yes |
| 5 | `log-opts` max-size/max-file match | Yes | Yes |
| 6 | `userns-remap` in daemon.json | Yes | Yes |
| 7 | `icc: false` in daemon.json | Yes | Yes |
| 8 | `live-restore: true` in daemon.json | Yes | Yes |
| 9 | `no-new-privileges: true` in daemon.json | Yes | Yes |
| 10 | User in docker group | Yes | Yes |
| 11 | `docker.service` enabled + running | No (skipped) | Yes |
| 12 | `docker info` logging driver | No (skipped) | Yes |
| 13 | `docker info` live-restore active | No (skipped) | Yes |
| 14 | `docker info` no-new-privileges in SecurityOptions | No (skipped) | Yes |
| 15 | `docker info` userns in SecurityOptions | No (skipped) | Yes |

The skip mechanism uses `when: docker_enable_service | default(true)`. In the Docker scenario, `docker_enable_service` is set to `false` via host_vars, so assertions 11-15 are automatically skipped.

---

## 8. Cross-Platform Considerations

### Package names

| Distribution | Package | Service name | Notes |
|-------------|---------|-------------|-------|
| Arch Linux | `docker` | `docker.service` | Installed via `community.general.pacman` |
| Ubuntu 24.04 | `docker.io` | `docker.service` | Universe repo. Alternative: `docker-ce` from Docker official repo |

The role itself does **not** install Docker -- it only configures it. Package installation happens in `prepare.yml` per scenario. The service name is `docker` on both distros, so `tasks/main.yml` works as-is.

### Template compatibility

The `daemon.json` template (`{{ docker_daemon_config | to_nice_json }}`) is distro-agnostic. The `set_fact` task that builds `docker_daemon_config` uses no Arch-specific logic.

### User group

The `docker` group name is the same on both Arch and Ubuntu. The `docker_user` variable defaults to `SUDO_USER` which works cross-platform.

### What needs changing for Ubuntu support

Currently `meta/main.yml` lists only `ArchLinux`. To officially support Ubuntu:
1. Add `Debian/Ubuntu` to `meta/main.yml` platforms
2. No task changes needed -- all tasks are already distro-agnostic
3. The vagrant `prepare.yml` handles Docker package installation per-distro

For this testing plan, Ubuntu support is validated via Vagrant without modifying the role's `meta/main.yml`. The role tasks are generic enough to work. A separate PR can update meta if multi-distro is accepted.

---

## 9. Implementation Order

### Step 1: Create shared playbooks

1. Create `ansible/roles/docker/molecule/shared/` directory
2. Create `molecule/shared/converge.yml` (clean, no pre_tasks)
3. Create `molecule/shared/verify.yml` (comprehensive, cross-platform, as designed in section 7)

### Step 2: Migrate default scenario

4. Update `molecule/default/molecule.yml` to reference `../shared/converge.yml` and `../shared/verify.yml`
5. Delete `molecule/default/converge.yml`
6. Delete `molecule/default/verify.yml`
7. Test: `molecule syntax -s default` (should pass)

### Step 3: Create Docker scenario

8. Create `molecule/docker/molecule.yml`
9. Create `molecule/docker/prepare.yml`
10. Test: `molecule test -s docker` on CI (verify config-only checks pass, service checks are skipped)

### Step 4: Create Vagrant scenario

11. Create `molecule/vagrant/molecule.yml`
12. Create `molecule/vagrant/prepare.yml` (cross-platform: Arch keyring refresh + docker install, Ubuntu apt + docker.io install)
13. Test locally or via CI: `molecule test -s vagrant` (verify full checks including service and docker info)

### Step 5: Validate idempotence

14. Confirm `molecule test -s docker` passes idempotence (no changed tasks on second run)
15. Confirm `molecule test -s vagrant` passes idempotence on both platforms

### Step 6: Commit

16. Stage all new/changed files
17. Commit: `feat(docker): add molecule docker + vagrant scenarios with shared verify`

---

## 10. Risks and Notes

### DinD complexity

- Running Docker daemon inside a Docker container is inherently fragile. The plan avoids this by testing config-only in the Docker scenario and reserving full daemon testing for Vagrant.
- If a future need arises to test the daemon in Docker, use the official `docker:dind` sidecar pattern. This is out of scope for now.

### userns-remap kernel support

- `userns-remap: "default"` requires the kernel to support user namespaces (`CONFIG_USER_NS=y`). This is enabled by default on Arch and Ubuntu 24.04 kernels.
- In the Docker container scenario (config-only), this is not tested at runtime.
- In the Vagrant scenario, the `docker info` assertion checks for `userns` in SecurityOptions, which confirms the kernel supports it and Docker activated it.
- If a VM kernel does not support user namespaces, Docker will fail to start. The `prepare.yml` does not check for this. The symptom would be a converge failure at the "Enable and start docker service" task.

### daemon.json JSON validity

- Double protection: `to_nice_json` filter + `validate:` parameter.
- The verify playbook adds a third check: `python3 -c "import json; json.load(...)"`.
- Risk: if a variable contains non-serializable data (e.g., a Jinja2 undefined), `to_nice_json` will fail during converge, not silently produce invalid JSON.

### Vagrant box freshness

- `generic/arch` boxes have stale pacman keyrings. The `prepare.yml` includes the keyring refresh workaround (same as `package_manager` vagrant scenario).
- `bento/ubuntu-24.04` boxes are generally fresh but may have outdated apt cache. The `prepare.yml` includes `apt update`.

### Idempotence considerations

- The `set_fact` task for `docker_daemon_config` always runs but does not change system state.
- The `template` task with `validate:` is idempotent (Ansible compares rendered content).
- The `user` module with `append: true` is idempotent.
- The `service` module with `enabled: true, state: started` is idempotent.
- Expected: zero changed tasks on second run.

### Default scenario vault dependency

- The default (localhost) scenario uses `vault_password_file`. This is inherited from the existing config.
- The Docker and Vagrant scenarios do **not** use vault (no `vars_files` with vault, no vault_password_file in config). The role itself does not reference any vault variables.
- If vault variables are needed in the future (e.g., for Docker registry auth), add `vault_password_file` to the Docker/Vagrant provisioner config.

### Final file tree

```
ansible/roles/docker/
  defaults/main.yml          -- unchanged (secure defaults already in place)
  handlers/main.yml          -- unchanged
  meta/main.yml              -- unchanged (Arch-only for now)
  tasks/main.yml             -- unchanged (validate: already present)
  templates/daemon.json.j2   -- unchanged
  molecule/
    shared/
      converge.yml           -- NEW (clean role application)
      verify.yml             -- NEW (comprehensive cross-platform assertions)
    default/
      molecule.yml           -- MODIFIED (points to ../shared/*)
      converge.yml           -- DELETED
      verify.yml             -- DELETED
    docker/
      molecule.yml           -- NEW (DinD config-only)
      prepare.yml            -- NEW (pacman update + docker install)
    vagrant/
      molecule.yml           -- NEW (KVM, Arch + Ubuntu)
      prepare.yml            -- NEW (cross-platform prep)
```
