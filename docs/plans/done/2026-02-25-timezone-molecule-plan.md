# Plan: timezone role -- Molecule shared migration + vagrant scenario

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/timezone/`

## 1. Current State

### Role behavior

The `timezone` role performs four actions:

1. **Install tzdata** -- uses `timezone_packages_tzdata` dict (keyed by `os_family`, with `default` fallback). The dict is not in `defaults/main.yml`; it comes from `group_vars/all/packages.yml` in production and is injected via `vars:` in molecule converge playbooks. The task is guarded by `when: timezone_packages_tzdata is defined`.
2. **Set timezone** -- `community.general.timezone` module sets `/etc/localtime` symlink and writes `/etc/timezone` on Debian. Notifies `restart cron` handler.
3. **Verify symlink** -- `readlink -f /etc/localtime` + assert that `timezone_name` is in the path.
4. **Report** -- includes `common` role report tasks (skipped in molecule via `skip-tags: report`).

**Handlers:** Two-step cron restart via `listen: restart cron`. Gathers `service_facts`, then restarts the distro-appropriate cron service only if present. Cron service name is mapped in `vars/main.yml` (`timezone_cron_service` dict: Archlinux=crond, Debian/Ubuntu=cron).

**Defaults:** Single variable `timezone_name: "UTC"`.

### Existing molecule scenarios

#### `molecule/default/` (localhost)

| File | Content |
|------|---------|
| `molecule.yml` | `driver: default` (managed: false), localhost, vault password file, test_sequence: syntax/converge/verify |
| `converge.yml` | `vars_files:` loads vault.yml, `pre_tasks:` asserts Arch only, applies role with `timezone_name: "Asia/Almaty"` and `timezone_packages_tzdata: {default: "tzdata"}` |
| `verify.yml` | Tests both systemd (`timedatectl show`) and non-systemd (`readlink -f /etc/localtime`) paths, asserts against `test_timezone: "Asia/Almaty"` |

#### `molecule/docker/` (Arch systemd container)

| File | Content |
|------|---------|
| `molecule.yml` | `driver: docker`, Archlinux-systemd image, privileged, cgroups, test_sequence includes idempotence, `skip-tags: report` |
| `converge.yml` | Minimal: applies role with `timezone_name: "Asia/Almaty"` and `timezone_packages_tzdata: {default: "tzdata"}`, no vault, no OS assertion |
| `verify.yml` | Checks `/etc/localtime` symlink via `readlink -f`, asserts tzdata installed via `pacman -Q tzdata`, no systemd/non-systemd branching |

### Key differences between scenarios

| Aspect | default | docker |
|--------|---------|--------|
| Vault loaded | Yes | No |
| OS assertion pre_task | Yes (Arch only) | No |
| verify: systemd path | Yes (branched) | No (readlink only) |
| verify: timedatectl | Yes (when systemd) | No |
| verify: tzdata package check | No | Yes (pacman -Q) |
| verify: gather_facts | Yes | No (gather_facts: false) |
| Idempotence check | No | Yes |

## 2. Cross-Platform Analysis

The timezone role is distro-agnostic by design. The `community.general.timezone` module handles the underlying differences:

| Mechanism | Arch Linux | Ubuntu 24.04 |
|-----------|-----------|--------------|
| Symlink | `/etc/localtime` -> `/usr/share/zoneinfo/<tz>` | Same |
| Timezone file | None (systemd reads symlink) | `/etc/timezone` (written by module) |
| timedatectl | Available (systemd) | Available (systemd) |
| tzdata package | `tzdata` (pacman) | `tzdata` (apt, pre-installed) |
| Cron service | `crond` (cronie) | `cron` (cron) |
| Package manager | pacman | apt |

Both Arch and Ubuntu VMs run systemd, so `timedatectl show --property=Timezone --value` works on both. The `readlink -f /etc/localtime` check also works on both as a secondary verification.

**tzdata package name:** `tzdata` on both Arch and Ubuntu. The `timezone_packages_tzdata` dict with `{default: "tzdata"}` covers both platforms without needing per-os_family entries (Gentoo is the only exception with `sys-libs/timezone-data`).

**Docker caveat:** In the systemd Docker container, `timedatectl` requires `systemd-timedated.service` to be running. The current docker verify avoids `timedatectl` entirely, using only `readlink`. This is correct -- `timedatectl` may fail in containers depending on D-Bus availability.

## 3. Shared Migration

### `molecule/shared/converge.yml` (merged)

The docker converge is the cleaner version. The default converge adds vault (not needed for timezone) and an Arch-only assertion (defeats multi-distro testing). The merged version takes the docker approach:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: timezone
      vars:
        timezone_name: "Asia/Almaty"
        timezone_packages_tzdata:
          default: "tzdata"
```

**Decisions:**
- No `vars_files` for vault -- timezone role does not use any vault variables.
- No `pre_tasks` OS assertion -- the role itself is distro-agnostic, and we want multi-distro testing in vagrant.
- `gather_facts: true` -- needed by the role for `ansible_facts['os_family']` in `timezone_packages_tzdata` lookup and handler logic.
- `timezone_packages_tzdata` passed as role var since it is not in `defaults/main.yml`.

### `molecule/shared/verify.yml` (merged)

The merged verify.yml combines the best checks from both scenarios with cross-platform guards:

```yaml
---
- name: Verify timezone role
  hosts: all
  become: true
  gather_facts: true

  vars:
    _tz_verify_expected: "Asia/Almaty"

  tasks:

    # ---- /etc/localtime symlink (all platforms) ----

    - name: Check /etc/localtime symlink target
      ansible.builtin.command: readlink -f /etc/localtime
      register: _tz_verify_localtime
      changed_when: false

    - name: Assert /etc/localtime points to expected timezone
      ansible.builtin.assert:
        that:
          - _tz_verify_expected in _tz_verify_localtime.stdout
        fail_msg: >-
          Expected '{{ _tz_verify_expected }}' in symlink target,
          got '{{ _tz_verify_localtime.stdout }}'

    # ---- timedatectl (systemd hosts only) ----

    - name: Check timezone via timedatectl (systemd)
      ansible.builtin.command: timedatectl show --property=Timezone --value
      register: _tz_verify_timedatectl
      changed_when: false
      failed_when: false
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert timedatectl reports expected timezone (systemd)
      ansible.builtin.assert:
        that:
          - _tz_verify_timedatectl.stdout == _tz_verify_expected
        fail_msg: >-
          timedatectl expected '{{ _tz_verify_expected }}',
          got '{{ _tz_verify_timedatectl.stdout }}'
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - _tz_verify_timedatectl.rc == 0

    # ---- tzdata package installed ----

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    - name: Assert tzdata package is installed
      ansible.builtin.assert:
        that:
          - "'tzdata' in ansible_facts.packages"
        fail_msg: "tzdata package not found in installed packages"

    # ---- /etc/timezone file (Debian/Ubuntu only) ----

    - name: Stat /etc/timezone
      ansible.builtin.stat:
        path: /etc/timezone
      register: _tz_verify_etc_timezone

    - name: Read /etc/timezone content
      ansible.builtin.slurp:
        src: /etc/timezone
      register: _tz_verify_etc_timezone_raw
      when: _tz_verify_etc_timezone.stat.exists

    - name: Assert /etc/timezone matches expected value (Debian/Ubuntu)
      ansible.builtin.assert:
        that:
          - (_tz_verify_etc_timezone_raw.content | b64decode | trim) == _tz_verify_expected
        fail_msg: >-
          /etc/timezone expected '{{ _tz_verify_expected }}',
          got '{{ _tz_verify_etc_timezone_raw.content | b64decode | trim }}'
      when: _tz_verify_etc_timezone.stat.exists

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          timezone verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}:
          /etc/localtime -> {{ _tz_verify_localtime.stdout }},
          tzdata installed
```

**Design notes:**
- Variable prefix `_tz_verify_` follows the project's `_rolename_verify_*` naming convention.
- `timedatectl` check uses `failed_when: false` so it does not break in Docker containers where `systemd-timedated` may not be running. The assertion is then guarded by `_tz_verify_timedatectl.rc == 0`.
- `package_facts` with `manager: auto` works cross-distro (pacman on Arch, apt on Ubuntu).
- `/etc/timezone` file check is guarded by `stat.exists` rather than `os_family == 'Debian'` -- more resilient and documents the actual filesystem state.
- No `pacman -Q tzdata` -- replaced by the cross-distro `package_facts` approach.

## 4. Docker Scenario Updates

### `molecule/docker/molecule.yml` (updated)

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
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - converge
    - idempotence
    - verify
    - destroy
```

**Changes from current:**
- Added `playbooks:` block pointing to `../shared/converge.yml` and `../shared/verify.yml`.
- Everything else unchanged -- same platform, same provisioner settings, same test sequence.

### `molecule/docker/converge.yml` -- DELETE

Replaced by `../shared/converge.yml`.

### `molecule/docker/verify.yml` -- DELETE

Replaced by `../shared/verify.yml`.

## 5. Default Scenario Updates

### `molecule/default/molecule.yml` (updated)

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
    - verify
```

**Changes from current:**
- Added `playbooks:` block pointing to shared files.
- Kept vault_password_file for consistency with other default scenarios (even though timezone itself does not use vault).
- No idempotence in default (matches current behavior -- localhost runs are destructive-free).

### `molecule/default/converge.yml` -- DELETE

Replaced by `../shared/converge.yml`.

### `molecule/default/verify.yml` -- DELETE

Replaced by `../shared/verify.yml`.

## 6. Vagrant Scenario

### `molecule/vagrant/molecule.yml`

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

**Notes:**
- Boxes match the template spec: `generic/arch` and `bento/ubuntu-24.04`.
- `skip-tags: report` -- the `common` report role is not available in molecule and should be skipped.
- `prepare` step included in test sequence for package cache refresh.
- Full test sequence with `idempotence` -- timezone role should be idempotent.

### `molecule/vagrant/prepare.yml`

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

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

This is an exact copy of `package_manager/molecule/vagrant/prepare.yml`. The same preparation steps are needed:
- **Python bootstrap:** `generic/arch` may not have Python installed.
- **Keyring refresh:** `generic/arch` ships with stale GPG keys; `pacman -Sy` fails without this.
- **Full upgrade:** Prevents partial-upgrade breakage (e.g., openssl mismatch).
- **apt cache update:** Ubuntu boxes may have stale apt cache.

## 7. Implementation Order

### Step 1: Create shared directory and files

```
mkdir -p ansible/roles/timezone/molecule/shared/
```

Create `molecule/shared/converge.yml` and `molecule/shared/verify.yml` as specified in Section 3.

### Step 2: Update docker scenario

1. Update `molecule/docker/molecule.yml` to add `playbooks:` block pointing to shared files (Section 4).
2. Delete `molecule/docker/converge.yml`.
3. Delete `molecule/docker/verify.yml`.

### Step 3: Verify docker scenario still passes

```bash
cd ansible/roles/timezone
molecule test -s docker
```

Expected: syntax, create, converge, idempotence, verify, destroy all pass. The shared verify.yml has `failed_when: false` on `timedatectl` so it should degrade gracefully in Docker.

### Step 4: Update default scenario

1. Update `molecule/default/molecule.yml` to add `playbooks:` block pointing to shared files (Section 5).
2. Delete `molecule/default/converge.yml`.
3. Delete `molecule/default/verify.yml`.

### Step 5: Verify default scenario still passes

```bash
cd ansible/roles/timezone
molecule test -s default
```

Expected: syntax, converge, verify pass on the local Arch Linux host.

### Step 6: Create vagrant scenario

```
mkdir -p ansible/roles/timezone/molecule/vagrant/
```

Create `molecule/vagrant/molecule.yml` and `molecule/vagrant/prepare.yml` as specified in Section 6.

### Step 7: Test vagrant scenario locally

```bash
cd ansible/roles/timezone
molecule test -s vagrant
```

Expected: Both `arch-vm` and `ubuntu-noble` pass all steps. The verify.yml should:
- Pass `/etc/localtime` symlink check on both.
- Pass `timedatectl` check on both (real systemd in VMs).
- Pass `package_facts` tzdata check on both.
- Pass `/etc/timezone` file check on Ubuntu only (file does not exist on Arch).

### Step 8: Commit

Single commit with all changes:
- New: `molecule/shared/converge.yml`, `molecule/shared/verify.yml`
- New: `molecule/vagrant/molecule.yml`, `molecule/vagrant/prepare.yml`
- Modified: `molecule/docker/molecule.yml`, `molecule/default/molecule.yml`
- Deleted: `molecule/docker/converge.yml`, `molecule/docker/verify.yml`, `molecule/default/converge.yml`, `molecule/default/verify.yml`

## 8. Risks / Notes

### Risk 1: timedatectl in Docker containers

`timedatectl show` requires `systemd-timedated.service` (a D-Bus-activated service). In Docker containers, D-Bus may not be fully functional even with systemd as PID 1. The shared verify handles this with `failed_when: false` on the timedatectl command and a `_tz_verify_timedatectl.rc == 0` guard on the assertion. If timedatectl fails, the test still passes via the `/etc/localtime` symlink check.

### Risk 2: generic/arch box stale keys

The `generic/arch` Vagrant box frequently ships with expired pacman GPG keys. The prepare.yml works around this by temporarily setting `SigLevel = Never`, refreshing `archlinux-keyring`, then restoring signature verification. This is a known pattern used in the `package_manager` vagrant scenario.

### Risk 3: Idempotence with timezone_packages_tzdata

The `timezone_packages_tzdata` variable is passed via converge vars, not from defaults. The `ansible.builtin.package` task with `state: present` is idempotent when the package is already installed. The `community.general.timezone` module is idempotent when the timezone is already set. No idempotence issues expected.

### Risk 4: Cron handler in test environments

The cron handler gathers `service_facts` and only restarts cron if the service is present. In Docker containers, cron may not be installed. In Vagrant VMs, cron is typically pre-installed (cronie on Arch, cron on Ubuntu). The handler's `when:` guard handles both cases correctly -- it will skip restart if cron is not found in `ansible_facts.services`.

### Risk 5: No prepare.yml for docker scenario

The current docker scenario has no prepare.yml and does not update the pacman cache. This works because the `arch-systemd` Docker image is built with an up-to-date package database. If tzdata is already installed in the image, the package task is a no-op. If not, `pacman -S tzdata` should succeed with the baked-in database. If this fails in practice, add a docker prepare.yml that runs `pacman -Sy` (matching the NTP docker pattern).

### Note: Vault removal from default scenario converge

The current default converge loads vault.yml. The shared converge does not. This is intentional -- the timezone role uses zero vault variables. The vault_password_file is still configured in `molecule/default/molecule.yml` for consistency with other default scenarios and to prevent errors if Ansible attempts to decrypt vault-encrypted variables from other sources.

### Note: Test timezone value

All scenarios use `"Asia/Almaty"` as the test timezone. This is a deliberate choice -- it is a non-UTC, non-US timezone that exercises the actual timezone-change path (the default is UTC).

## File tree after implementation

```
ansible/roles/timezone/molecule/
  shared/
    converge.yml          # NEW -- merged from docker+default
    verify.yml            # NEW -- merged with cross-platform guards
  default/
    molecule.yml          # MODIFIED -- playbooks point to ../shared/
  docker/
    molecule.yml          # MODIFIED -- playbooks point to ../shared/
  vagrant/
    molecule.yml          # NEW -- libvirt, arch-vm + ubuntu-noble
    prepare.yml           # NEW -- keyring fix, apt cache, python bootstrap
```
