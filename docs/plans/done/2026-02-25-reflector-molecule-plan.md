# reflector: Molecule Testing Scenarios -- Plan

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### Role purpose

The `reflector` role configures and runs [reflector](https://wiki.archlinux.org/title/Reflector) to maintain an optimized Arch Linux pacman mirror list. It performs five operations:

1. **Install** -- ensures the `reflector` package is present via `community.general.pacman`.
2. **Configure** -- deploys `/etc/xdg/reflector/reflector.conf` from a Jinja2 template, creates a systemd timer drop-in with `OnCalendar` and `RandomizedDelaySec`, and optionally deploys a pacman hook (`/etc/pacman.d/hooks/reflector-mirrorlist.hook`) that re-runs reflector when `pacman-mirrorlist` is upgraded.
3. **Service** -- enables and starts `reflector.timer` with `daemon_reload: true`.
4. **Update** -- backs up the current mirrorlist, runs `reflector` with retries, validates the new mirrorlist contains `Server =` entries, rotates old backups (keep N newest), and reports whether the mirrorlist changed. On failure, the `rescue` block restores from backup.
5. **Pacman cache refresh** -- `update_cache: true` after mirrorlist update.

### Variables (defaults/main.yml)

| Variable | Default | Purpose |
|----------|---------|---------|
| `reflector_countries` | `"KZ,RU,DE,NL,FR"` | Comma-separated country codes for mirror selection |
| `reflector_protocol` | `"https"` | Mirror protocol |
| `reflector_latest` | `20` | Number of mirrors to keep |
| `reflector_sort` | `"rate"` | Sort method (rate, age, score, country) |
| `reflector_age` | `12` | Maximum mirror age in hours |
| `reflector_timer_schedule` | `"daily"` | Systemd OnCalendar value |
| `reflector_threads` | `4` | Parallel download threads |
| `reflector_conf_path` | `/etc/xdg/reflector/reflector.conf` | Config file path |
| `reflector_mirrorlist_path` | `/etc/pacman.d/mirrorlist` | Output mirrorlist path |
| `reflector_backup_mirrorlist` | `true` | Create timestamped backup before update |
| `reflector_retries` | `3` | Retry count for reflector command |
| `reflector_retry_delay` | `5` | Seconds between retries |
| `reflector_connection_timeout` | `10` | Connection timeout in seconds |
| `reflector_download_timeout` | `30` | Download timeout in seconds |
| `reflector_proxy` | `""` | HTTP/HTTPS proxy (empty = no proxy) |
| `reflector_backup_keep` | `3` | Max backup files to retain (0 = unlimited) |
| `reflector_timer_randomized_delay` | `"1h"` | RandomizedDelaySec for timer |
| `reflector_pacman_hook` | `true` | Deploy pacman hook for auto-update on mirror package upgrade |

### Task files

```
tasks/
  main.yml        -- assert Arch, import install/configure/service/update
  install.yml     -- pacman: reflector state=latest
  configure.yml   -- template reflector.conf, timer drop-in, pacman hook
  service.yml     -- systemd: enable+start reflector.timer
  update.yml      -- backup, run reflector, validate, rotate, report; rescue on failure
templates/
  reflector.conf.j2  -- reflector CLI flags as config file
files/
  reflector-mirrorlist.hook  -- pacman alpm hook
handlers/
  main.yml        -- "Reload systemd" (daemon_reload)
```

### Existing molecule scenario

```
molecule/
  default/
    molecule.yml    -- driver: default (localhost), vault_password_file, no create/destroy
    converge.yml    -- assert os_family==Archlinux, load vault.yml, apply reflector role
    verify.yml      -- 13 checks (see below)
  README.md         -- Russian-language documentation for localhost testing
```

The existing `molecule/default/` scenario uses the delegated driver against localhost. It runs on the developer's Arch VM, modifies the real system, and requires a VM snapshot for safety. The test sequence is `syntax -> converge -> verify` (no idempotence check, no create/destroy).

### Existing verify checks (13 assertions)

1. reflector package installed (check_mode pacman)
2. `/etc/xdg/reflector/reflector.conf` exists
3. Config contains `--save` and `--protocol`
4. Timer drop-in override exists at `/etc/systemd/system/reflector.timer.d/override.conf`
5. `reflector.timer` is enabled
6. `reflector.timer` is active
7. Mirrorlist exists and is non-empty
8. Mirrorlist contains at least 1 `Server =` entry
9. Pacman hooks directory exists
10. Pacman hook file exists
11. Hook content contains `pacman-mirrorlist` and `--config`
12. Timer drop-in contains `RandomizedDelaySec`
13. Backup count <= `reflector_backup_keep`
14. Mirrorlist contains >= 3 `Server =` entries (stricter than check 8)
15. Summary debug message

### Issues with existing test setup

- **No shared playbooks**: converge.yml and verify.yml live in `molecule/default/`, not reusable by docker/vagrant scenarios.
- **Vault dependency**: converge.yml loads `vault.yml`. The vault file is not needed by the reflector role itself (no vault-encrypted variables are used by this role). This is a leftover from an earlier template.
- **No idempotence test**: the `update.yml` tasks that run the `reflector` command are not idempotent (they always execute). Idempotence testing requires `skip-tags: update` or `skip-tags: mirrors` to avoid false failures.
- **Network-dependent verification**: checks 8 and 14 (Server count) only pass if the `reflector` command successfully fetched mirrors. In Docker containers without internet, these will fail.

## 2. Arch-Only Note

The reflector role is **Arch Linux exclusive** by design:

- `tasks/main.yml` line 1: hard assert `ansible_facts['os_family'] == 'Archlinux'`
- `meta/main.yml`: `platforms: [{name: ArchLinux, versions: [all]}]`
- The `reflector` binary is an Arch Linux package that reads/writes pacman mirrorlist
- The pacman hook mechanism (`/etc/pacman.d/hooks/`) is pacman-specific
- The systemd timer `reflector.timer` is shipped by the Arch `reflector` package

**No Ubuntu/Debian platform is included in any scenario.** The vagrant scenario runs a single Arch VM (`generic/arch`). There is no cross-platform testing dimension for this role.

## 3. Known Bugs / Recent Fixes

### Fixed: variable name inconsistency (commit c0acedf)

Commit `c0acedf` (2026-02-25) corrected two variable references in `tasks/update.yml`:

1. `register: reflector_backups` changed to `register: _reflector_backups` -- the leading underscore indicates a block-scoped internal register (project convention). All references to this variable within the block already used `_reflector_backups`.

2. `_reflector_old_mirror.content` changed to `reflector_old_mirror.content` -- this variable is registered outside the block at line 16 as `reflector_old_mirror` (no underscore). The reference inside the block was incorrectly prefixed.

**Current status**: both fixes are applied. `tasks/update.yml` now has consistent variable names throughout. No remaining `_reflector_` prefix issues.

### Observation: handler lacks `listen:` directive

`handlers/main.yml` defines `"Reload systemd"` without a `listen:` directive. Project convention (documented in MEMORY.md) is to use `listen:` for cross-role notification. This is a minor style issue, not a bug -- the handler works correctly as-is because only `configure.yml` within this role notifies it.

### Observation: vault.yml loaded but not used

The existing `converge.yml` loads `{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml` via `vars_files`. The reflector role does not use any vault-encrypted variables. The shared converge.yml should drop this dependency.

## 4. Shared Migration

### Current structure

```
molecule/
  default/
    molecule.yml
    converge.yml   <-- to be moved
    verify.yml     <-- to be moved
  README.md
```

### Target structure

```
molecule/
  shared/
    converge.yml   <-- rewritten (no vault, no pre_tasks assert)
    verify.yml     <-- adapted from default/verify.yml (split online/offline checks)
  default/
    molecule.yml   <-- updated to point to ../shared/
  docker/
    molecule.yml
    prepare.yml
  vagrant/
    molecule.yml
    prepare.yml
  README.md
```

### shared/converge.yml

The converge playbook is simplified: no vault loading (the role uses no vault variables), no pre_tasks assertion (the role itself asserts `os_family == Archlinux` at the top of `tasks/main.yml`).

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: reflector
```

This matches the ntp role's `shared/converge.yml` pattern exactly.

### shared/verify.yml

The verify playbook must be adapted for environments where the `reflector` command may not have been run (e.g., when `update` tag is skipped in Docker). The strategy is:

- **Always check**: package installed, config file exists and valid, timer drop-in exists and valid, timer enabled, pacman hook deployed.
- **Conditionally check** (only when mirrorlist exists and has content): Server entry count, backup rotation.
- Timer `ActiveState` check needs special handling in Docker (timer may not be active if systemd is not fully running).

Details in section 7 below.

### default/molecule.yml update

The existing `molecule/default/molecule.yml` needs two changes:

1. Remove `vault_password_file` from provisioner config (no longer needed).
2. Update playbook paths to `../shared/converge.yml` and `../shared/verify.yml`.

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
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

No idempotence step in default -- same as before. The localhost scenario is for quick manual testing on the developer's Arch VM.

## 5. Docker Scenario

### Network requirements

The reflector role's `update.yml` fetches mirror information from the internet. In a Docker container:

- **With network**: `reflector` can run successfully, mirrorlist gets populated, all verify checks pass.
- **Without network**: `reflector` fails (even with retries). The `rescue` block tries to restore a backup that does not exist (first run), causing the role to fail.

**Strategy**: use `skip-tags: mirrors` in the Docker scenario provisioner to skip the `update.yml` tasks entirely. The `update` tag is applied to all tasks in `update.yml`. However, looking at the actual tags in the role, the `update.yml` tasks use `tags: ['update']`. The `mirrors` tag is used at the playbook level (in `workstation.yml`) but not within the role itself.

**Corrected strategy**: use `skip-tags: update` to skip all tasks in `update.yml`. This allows testing of install, configure, and service tasks without network dependency. The Docker container will have:
- reflector package installed
- reflector.conf deployed
- timer drop-in configured
- timer enabled
- pacman hook deployed
- **No mirrorlist update** (skipped)

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
    skip-tags: update
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

**Design decisions:**

- `skip-tags: update` -- skips the network-dependent `update.yml` tasks. The install, configure, and service tasks are all testable offline (the `reflector` package is pre-installed in the arch-systemd image, or installed via `pacman` if the image has a cache).
- `dns_servers: [8.8.8.8, 8.8.4.4]` -- ensures DNS resolution works inside the container for package installation. Even with `skip-tags: update`, the `install.yml` task runs `pacman -S reflector` which needs network/cache.
- **Idempotence included** -- with `update` skipped, the remaining tasks (template, copy, systemd enable) are all idempotent. Second converge should produce zero changes.
- No vault configuration -- the role uses no vault variables.

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

Identical to the ntp role's `docker/prepare.yml`. The arch-systemd Docker image ships with a pacman cache that may be stale. Refreshing the cache ensures `pacman -S reflector` succeeds.

### What Docker tests vs. what it skips

| Component | Docker (skip-tags: update) | Reason |
|-----------|---------------------------|--------|
| Package install | Tested | `pacman -S reflector` works in container |
| reflector.conf template | Tested | No network needed |
| Timer drop-in | Tested | File creation only |
| Timer enable/start | Tested | Systemd in privileged container |
| Pacman hook deploy | Tested | File copy only |
| `reflector` command execution | **Skipped** | Requires internet + working mirrors |
| Mirrorlist validation | **Skipped** | No mirrorlist generated |
| Backup rotation | **Skipped** | No backups created |
| Rollback (rescue block) | **Skipped** | Only triggers on reflector failure |

## 6. Vagrant Scenario

The vagrant scenario runs the full role including the `update.yml` tasks. Vagrant VMs have full network access, so reflector can fetch mirrors. This provides end-to-end validation.

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
    - verify
    - destroy
```

**Design decisions:**

- **Single platform: `arch-vm` only.** Reflector is Arch-exclusive. No Ubuntu platform.
- `skip-tags: report` -- consistent with other vagrant scenarios. The `common` role report tasks are not relevant in molecule.
- `memory: 2048` / `cpus: 2` -- project standard for vagrant scenarios (matches `package_manager` vagrant).
- **No idempotence step.** The `update.yml` tasks always execute `reflector` (with `changed_when: false` on the command, but with a `set_fact` + `changed_when` on the report task). The backup creation also produces changes on each run. Idempotence would require `skip-tags: update`, which defeats the purpose of the vagrant full-network scenario. If idempotence testing of the config/service layer is desired, the Docker scenario already covers that.
- `box: generic/arch` -- community-maintained Arch Linux box with libvirt support. Known issue: stale pacman keyring (handled in prepare.yml).

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
```

This is the Arch-only subset of the `package_manager/molecule/vagrant/prepare.yml`. The Ubuntu tasks are omitted because this scenario only has an Arch platform. The three-step bootstrap is required:

1. **Python**: `generic/arch` may lack Python. Ansible needs it for all modules except `raw`.
2. **Keyring refresh**: The box ships with a keyring snapshot from build time. Rolling-release Arch updates require current keys.
3. **Full upgrade**: Ensures library compatibility for `reflector` and its Python dependencies.

## 7. Verify.yml Design

### Strategy: split checks into offline (always) and online (conditional)

The shared verify playbook must work in both Docker (no mirrorlist update) and Vagrant (full update) scenarios. The approach:

- **Offline checks** run unconditionally -- they verify config, files, and service state.
- **Online checks** are guarded by `when: reflector_verify_mirrorlist.stat.exists and reflector_verify_mirrorlist.stat.size > 0` -- they only run when a mirrorlist was actually generated.

### shared/verify.yml

```yaml
---
- name: Verify reflector role
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

    - name: Assert reflector package is installed
      ansible.builtin.assert:
        that: "'reflector' in ansible_facts.packages"
        fail_msg: "reflector package not found"

    # ---- Config file ----

    - name: Stat reflector config
      ansible.builtin.stat:
        path: "{{ reflector_conf_path }}"
      register: reflector_verify_conf

    - name: Assert reflector config exists
      ansible.builtin.assert:
        that:
          - reflector_verify_conf.stat.exists
          - reflector_verify_conf.stat.isreg
          - reflector_verify_conf.stat.pw_name == 'root'
          - reflector_verify_conf.stat.mode == '0644'
        fail_msg: "{{ reflector_conf_path }} missing or wrong permissions"

    - name: Read reflector config content
      ansible.builtin.slurp:
        src: "{{ reflector_conf_path }}"
      register: reflector_verify_conf_raw

    - name: Set config text fact
      ansible.builtin.set_fact:
        reflector_verify_conf_text: "{{ reflector_verify_conf_raw.content | b64decode }}"

    - name: Assert config contains expected directives
      ansible.builtin.assert:
        that:
          - "'--protocol ' ~ reflector_protocol in reflector_verify_conf_text"
          - "'--sort ' ~ reflector_sort in reflector_verify_conf_text"
          - "'--latest ' ~ reflector_latest | string in reflector_verify_conf_text"
          - "'--age ' ~ reflector_age | string in reflector_verify_conf_text"
          - "'--country ' ~ reflector_countries in reflector_verify_conf_text"
          - "'--save ' ~ reflector_mirrorlist_path in reflector_verify_conf_text"
        fail_msg: "reflector.conf missing expected directives"

    # ---- Timer drop-in ----

    - name: Stat timer drop-in
      ansible.builtin.stat:
        path: /etc/systemd/system/reflector.timer.d/override.conf
      register: reflector_verify_dropin

    - name: Assert timer drop-in exists
      ansible.builtin.assert:
        that:
          - reflector_verify_dropin.stat.exists
          - reflector_verify_dropin.stat.isreg
        fail_msg: "Timer drop-in /etc/systemd/system/reflector.timer.d/override.conf missing"

    - name: Read timer drop-in content
      ansible.builtin.slurp:
        src: /etc/systemd/system/reflector.timer.d/override.conf
      register: reflector_verify_dropin_raw

    - name: Assert timer drop-in contains expected values
      ansible.builtin.assert:
        that:
          - "'OnCalendar=' ~ reflector_timer_schedule in (reflector_verify_dropin_raw.content | b64decode)"
          - "'RandomizedDelaySec=' ~ reflector_timer_randomized_delay in (reflector_verify_dropin_raw.content | b64decode)"
        fail_msg: "Timer drop-in missing OnCalendar or RandomizedDelaySec"

    # ---- Timer service state ----

    - name: Check reflector.timer is enabled
      ansible.builtin.command: systemctl is-enabled reflector.timer
      register: reflector_verify_timer_enabled
      changed_when: false
      failed_when: reflector_verify_timer_enabled.rc != 0

    - name: Assert reflector.timer is enabled
      ansible.builtin.assert:
        that: reflector_verify_timer_enabled.stdout == 'enabled'
        fail_msg: "reflector.timer is not enabled (got: {{ reflector_verify_timer_enabled.stdout }})"

    # ---- Pacman hook ----

    - name: Stat pacman hooks directory
      ansible.builtin.stat:
        path: /etc/pacman.d/hooks
      register: reflector_verify_hooks_dir
      when: reflector_pacman_hook | bool

    - name: Assert pacman hooks directory exists
      ansible.builtin.assert:
        that:
          - reflector_verify_hooks_dir.stat.exists
          - reflector_verify_hooks_dir.stat.isdir
        fail_msg: "/etc/pacman.d/hooks directory missing"
      when: reflector_pacman_hook | bool

    - name: Stat pacman hook file
      ansible.builtin.stat:
        path: /etc/pacman.d/hooks/reflector-mirrorlist.hook
      register: reflector_verify_hook
      when: reflector_pacman_hook | bool

    - name: Assert pacman hook file exists
      ansible.builtin.assert:
        that:
          - reflector_verify_hook.stat.exists
          - reflector_verify_hook.stat.isreg
        fail_msg: "Pacman hook /etc/pacman.d/hooks/reflector-mirrorlist.hook missing"
      when: reflector_pacman_hook | bool

    - name: Read pacman hook content
      ansible.builtin.slurp:
        src: /etc/pacman.d/hooks/reflector-mirrorlist.hook
      register: reflector_verify_hook_raw
      when: reflector_pacman_hook | bool

    - name: Assert hook content references pacman-mirrorlist and --config
      ansible.builtin.assert:
        that:
          - "'pacman-mirrorlist' in (reflector_verify_hook_raw.content | b64decode)"
          - "'--config' in (reflector_verify_hook_raw.content | b64decode)"
        fail_msg: "Hook file missing expected content (pacman-mirrorlist or --config)"
      when: reflector_pacman_hook | bool

    # ---- Mirrorlist (online checks -- only when update was run) ----

    - name: Stat mirrorlist
      ansible.builtin.stat:
        path: "{{ reflector_mirrorlist_path }}"
      register: reflector_verify_mirrorlist

    - name: Validate mirrorlist contains Server entries
      ansible.builtin.command: grep -c '^Server = ' {{ reflector_mirrorlist_path }}
      register: reflector_verify_server_count
      changed_when: false
      failed_when: reflector_verify_server_count.stdout | int < 3
      when:
        - reflector_verify_mirrorlist.stat.exists
        - reflector_verify_mirrorlist.stat.size > 0

    # ---- Backup rotation (online checks -- only when backups exist) ----

    - name: Count mirrorlist backup files
      ansible.builtin.find:
        paths: "{{ reflector_mirrorlist_path | dirname }}"
        patterns: "mirrorlist.bak.*"
      register: reflector_verify_backups
      when:
        - reflector_verify_mirrorlist.stat.exists
        - reflector_backup_mirrorlist | bool

    - name: Assert backup count does not exceed reflector_backup_keep
      ansible.builtin.assert:
        that:
          - reflector_verify_backups.matched <= reflector_backup_keep | int
        fail_msg: >
          Found {{ reflector_verify_backups.matched }} backup files,
          expected <= {{ reflector_backup_keep }}
      when:
        - reflector_verify_backups is defined
        - reflector_verify_backups is not skipped
        - reflector_backup_keep | int > 0

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Reflector verify passed: package installed, config deployed at
          {{ reflector_conf_path }}, timer drop-in configured, timer enabled,
          pacman hook {{ 'deployed' if reflector_pacman_hook | bool else 'skipped' }}.
          Mirrorlist: {{ 'validated (' ~ reflector_verify_server_count.stdout | default('N/A') ~ ' servers)'
          if (reflector_verify_mirrorlist.stat.exists and reflector_verify_mirrorlist.stat.size > 0)
          else 'not checked (update was skipped)' }}.
```

### Key design choices

1. **`vars_files: ../../defaults/main.yml`** -- loads role defaults so assertions can reference `reflector_conf_path`, `reflector_countries`, etc. This is necessary because the verify playbook runs standalone, not as part of the role. This pattern is documented in project memory (`molecule-testing.md`).

2. **`systemctl is-enabled` instead of `service_facts`** -- project-wide finding: `service_facts` does not reliably include `.timer` units (ansible/ansible#78107). Using `command: systemctl is-enabled reflector.timer` is the proven workaround from the ntp role.

3. **No `ActiveState` check** -- the existing verify checks `reflector.timer` ActiveState == 'active'. In Docker containers, timers may not be active even when enabled (systemd may not have fully started the timer subsystem). The enabled check is sufficient for correctness. The vagrant scenario could optionally add an active check, but keeping a single shared verify.yml is simpler.

4. **Config content assertions use variable interpolation** -- instead of hardcoded strings like `'--save'`, the assertions check for `'--protocol ' ~ reflector_protocol`. This validates that the template correctly rendered the variable values, not just that the flags exist.

5. **Online checks are conditional** -- the mirrorlist server count and backup rotation checks are guarded by `when: reflector_verify_mirrorlist.stat.exists`. In Docker with `skip-tags: update`, no mirrorlist is generated, so these checks are safely skipped.

## 8. Implementation Order

1. **Create `molecule/shared/` directory and move playbooks.**
   - Create `molecule/shared/converge.yml` (simplified: no vault, no pre_tasks).
   - Create `molecule/shared/verify.yml` (rewritten with offline/online split and variable-based assertions).
   - Do NOT delete `molecule/default/converge.yml` and `molecule/default/verify.yml` yet -- update default/molecule.yml first.

2. **Update `molecule/default/molecule.yml`.**
   - Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`.
   - Remove `vault_password_file` from provisioner config.
   - Test: `cd ansible/roles/reflector && molecule syntax -s default` to verify paths resolve.

3. **Delete old `molecule/default/converge.yml` and `molecule/default/verify.yml`.**
   - Only after confirming default scenario works with shared playbooks.

4. **Create `molecule/docker/` scenario.**
   - `molecule/docker/molecule.yml` -- as specified in section 5.
   - `molecule/docker/prepare.yml` -- pacman cache update.
   - Test: `cd ansible/roles/reflector && molecule test -s docker`.
   - Expected: all steps pass (syntax, create, prepare, converge, idempotence, verify, destroy).
   - The idempotence step should show zero changes (with `update` skipped).

5. **Create `molecule/vagrant/` scenario.**
   - `molecule/vagrant/molecule.yml` -- as specified in section 6.
   - `molecule/vagrant/prepare.yml` -- Python bootstrap, keyring refresh, full upgrade.
   - Test: `cd ansible/roles/reflector && molecule test -s vagrant`.
   - Expected: all steps pass. The `reflector` command runs with network access, mirrorlist is populated, all verify checks (including online checks) pass.

6. **Update `molecule/README.md`** (optional).
   - Document the three scenarios: default (localhost), docker (offline config test), vagrant (full end-to-end).

7. **Commit.**
   - Files added: `molecule/shared/converge.yml`, `molecule/shared/verify.yml`, `molecule/docker/molecule.yml`, `molecule/docker/prepare.yml`, `molecule/vagrant/molecule.yml`, `molecule/vagrant/prepare.yml`.
   - Files modified: `molecule/default/molecule.yml`.
   - Files deleted: `molecule/default/converge.yml`, `molecule/default/verify.yml`.

## 9. Risks / Notes

### Medium risk: network access in Docker for package install

Even with `skip-tags: update`, the `install.yml` task runs `pacman -S reflector`. If the Docker container cannot reach the Arch mirrors (network isolation, DNS failure), package installation fails and the converge step fails.

**Mitigation**: The `arch-systemd` Docker image should pre-install `reflector` as part of the image build. If it does not, the `prepare.yml` updates the pacman cache and the `dns_servers` config ensures DNS works.

### Medium risk: reflector command timeout in vagrant

The `reflector` command in `update.yml` has `connection_timeout: 10` and `download_timeout: 30` (seconds). With retries (3 attempts, 5s delay), worst-case wall time is ~135 seconds. If the vagrant VM has slow network (e.g., behind a corporate proxy), this can make tests slow but should not cause molecule-level timeouts.

**Mitigation**: The default timeouts are reasonable. If tests are consistently slow, increase `reflector_connection_timeout` and `reflector_download_timeout` in the vagrant converge vars, or override in molecule provisioner `inventory.group_vars`.

### Low risk: stale generic/arch vagrant box

The `generic/arch` box is community-maintained. If the box becomes severely outdated (months behind), the pacman keyring workaround in `prepare.yml` handles most staleness. If the box image is completely broken (removed from Vagrant Cloud), switch to `archlinux/archlinux` (official Arch box, also supports libvirt).

### Low risk: timer state in Docker

Systemd timers in Docker containers may behave differently from bare-metal. The timer can be `enabled` but not `active` if the systemd timer subsystem has not completed initialization. The verify playbook checks `is-enabled` only (not `ActiveState`), which is reliable in Docker.

### Note: idempotence and the `update` tag

The Docker scenario includes idempotence testing because `skip-tags: update` removes all non-idempotent tasks. The vagrant scenario omits idempotence because the full role (with `update.yml`) is not idempotent -- `reflector` always runs, backups are always created, and the report task uses `changed_when: mirrorlist_changed`.

If idempotence testing of the full role is ever desired, the role would need to add a `reflector_run_update: true` variable that can be set to `false` on second run. This is out of scope for this plan.

### Note: no CI workflow included

This plan creates the molecule scenario files only. Integration into a CI workflow (`.github/workflows/`) is out of scope. The scenarios are assumed to be run manually (`molecule test -s docker`, `molecule test -s vagrant`) or picked up by a future centralized CI workflow.

## File Summary

| Action | File | Purpose |
|--------|------|---------|
| Create | `molecule/shared/converge.yml` | Shared converge: apply reflector role (no vault, no arch assert) |
| Create | `molecule/shared/verify.yml` | Shared verify: offline + conditional online checks |
| Create | `molecule/docker/molecule.yml` | Docker scenario: arch-systemd, skip-tags: update, with idempotence |
| Create | `molecule/docker/prepare.yml` | Docker prepare: update pacman cache |
| Create | `molecule/vagrant/molecule.yml` | Vagrant scenario: generic/arch, full role, no idempotence |
| Create | `molecule/vagrant/prepare.yml` | Vagrant prepare: Python bootstrap, keyring refresh, full upgrade |
| Modify | `molecule/default/molecule.yml` | Point to shared playbooks, remove vault config |
| Delete | `molecule/default/converge.yml` | Replaced by shared/converge.yml |
| Delete | `molecule/default/verify.yml` | Replaced by shared/verify.yml |
