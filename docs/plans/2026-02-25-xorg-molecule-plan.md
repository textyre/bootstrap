# Plan: xorg role -- Docker + Vagrant molecule scenarios

**Date:** 2026-02-25
**Role:** `ansible/roles/xorg/`
**Status:** Draft

## 1. Current State

### What the Role Does

The xorg role deploys X11 configuration files from the repository's `dotfiles/` directory to `/etc/X11/xorg.conf.d/` on the target host. It does NOT install packages, manage services, or use templates.

Execution pipeline:

1. **Stat source directory** -- verifies `xorg_source_dir` (defaults to `dotfiles/` in the repo root) exists.
2. **Assert source directory** -- fails if the source directory is missing. **NOTE: Bug on line 14-15 of `tasks/main.yml` -- registers `xorg_source_stat` but asserts on `_xorg_source_stat` (leading underscore). This will always fail. Must be fixed before Docker/Vagrant testing.**
3. **Create directories** -- ensures `/etc/X11/xorg.conf.d/` exists with `root:root 0755`.
4. **Deploy configs** -- copies files from `xorg_source_dir` to `/etc/X11/xorg.conf.d/` using `ansible.builtin.copy` with `remote_src: true`. Two files are deployed:
   - `00-keyboard.conf` -- XKB layout (US+RU, toggle with Ctrl+Space)
   - `10-monitor.conf` -- monitor/screen/device config (2560x1440, modesetting driver)
5. **Report** -- debug message showing file count (tagged `xorg`).

### Key Variable

```yaml
xorg_source_dir: "{{ dotfiles_base_dir | default(lookup('env', 'REPO_ROOT') ~ '/dotfiles', true) }}"
```

The `remote_src: true` parameter in the copy task means the source files must exist **on the target host**, not on the Ansible controller. For localhost testing this is transparent. For Docker/Vagrant, the dotfiles must be provisioned onto the target or the variable must be overridden.

### Deployed Configuration Files

| Source (relative to `xorg_source_dir`) | Destination | Contents |
|----------------------------------------|-------------|----------|
| `etc/X11/xorg.conf.d/00-keyboard.conf` | `/etc/X11/xorg.conf.d/00-keyboard.conf` | XKB layout: us,ru; toggle grp:ctrl_space_toggle |
| `etc/X11/xorg.conf.d/10-monitor.conf` | `/etc/X11/xorg.conf.d/10-monitor.conf` | Monitor0, Card0 (modesetting), Screen0, 2560x1440_60 |

### Existing Scenarios

| Scenario | Driver | Platforms | Prepare | Converge | Verify |
|----------|--------|-----------|---------|----------|--------|
| `default` | default (localhost) | Localhost only | none | converge.yml (local) | verify.yml (local) |

No Docker or Vagrant scenarios exist. No `molecule/shared/` directory exists.

### Existing Test Coverage

The current `verify.yml` checks only:
1. `/etc/X11/xorg.conf.d/10-monitor.conf` exists
2. `10-monitor.conf` has `root:root 0644` permissions

**Gaps:** `00-keyboard.conf` is never verified. No content checks. No package installation checks (role does not install packages, but tests could verify the target directory exists).

### Role Metadata

- `meta/main.yml` lists only ArchLinux as a supported platform.
- `dependencies: []` -- no role dependencies.
- No templates, no handlers, no vars directory.

### Bug: Register Name Mismatch

In `tasks/main.yml`:
- Line 8: `register: xorg_source_stat`
- Lines 14-15: references `_xorg_source_stat.stat.exists` and `_xorg_source_stat.stat.isdir`

The leading underscore makes the assert always fail because `_xorg_source_stat` is undefined. The default scenario's `converge.yml` loads vault.yml and runs on localhost where `REPO_ROOT` must be set for the role to find dotfiles. This bug may be masked if the assert task is somehow not reached or if the variable was renamed in an incomplete refactor.

**This must be fixed (rename `_xorg_source_stat` to `xorg_source_stat` in the assert) before any molecule scenario will pass.**

## 2. Display Limitation

Xorg server requires display hardware (physical GPU or virtual framebuffer) to start. Neither Docker containers nor headless VMs have a display by default.

**What CAN be tested without a display:**
- Package installation (xorg-server, xorg-xinit, etc.) -- though the current role does NOT install packages
- Config file deployment to `/etc/X11/xorg.conf.d/`
- File permissions and ownership
- Config file content validation (keyboard layout, monitor settings)
- Directory creation (`/etc/X11/xorg.conf.d/`)

**What CANNOT be tested:**
- Xorg server startup (`startx`, `xinit`)
- Display resolution actually applied
- Keyboard layout switching in a running X session
- Driver loading (modesetting, vmware, etc.)

**Strategy:** Test config file deployment only. This covers the role's actual responsibility. Xorg server startup is tested manually or in integration environments with display hardware.

## 3. Cross-Platform Analysis

### Current Role Scope

The role currently deploys static config files. It does NOT install packages, which means the cross-platform analysis focuses on:
1. Config file paths -- where Xorg looks for config snippets
2. Config file format -- whether the same `.conf` syntax works across distros
3. If package installation is added later, which packages to install

### X11 Config Paths

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| System config snippets | `/etc/X11/xorg.conf.d/` | `/etc/X11/xorg.conf.d/` |
| Distro defaults (read-only) | `/usr/share/X11/xorg.conf.d/` | `/usr/share/X11/xorg.conf.d/` |
| Config file format | Standard Xorg `Section` blocks | Identical format |
| Config file load order | Alphabetical within each directory | Identical behavior |
| `/etc/X11/` priority | Overrides `/usr/share/X11/` | Identical behavior |

Both distributions use the same `/etc/X11/xorg.conf.d/` path for admin-provided configuration snippets. The Xorg config format (`Section "..." ... EndSection`) is universal across all distributions. **No path adaptation is needed.**

### X11 Package Names (if package install is added)

| Component | Arch Linux | Ubuntu 24.04 |
|-----------|-----------|--------------|
| Xorg server | `xorg-server` | `xserver-xorg` |
| xinit (startx) | `xorg-xinit` | `xinit` |
| X utilities | `xorg-xrandr`, `xorg-xdpyinfo` | `x11-xserver-utils` (includes xrandr, xdpyinfo) |
| XKB data | `xkeyboard-config` | `xkb-data` |
| Modesetting driver | Built into `xorg-server` | Built into `xserver-xorg-core` |

The role currently does not install packages, so these are informational for future cross-platform expansion.

### `/usr/share/X11/xorg.conf.d/` Conflict Risk

Both distros ship default configs in `/usr/share/X11/xorg.conf.d/`:
- Arch: `10-quirks.conf`, `40-libinput.conf` (from `xf86-input-libinput`)
- Ubuntu: `10-quirks.conf`, `40-libinput.conf`, `70-synaptics.conf`

Files in `/etc/X11/xorg.conf.d/` override `/usr/share/X11/xorg.conf.d/` when they share the same filename prefix number. The role's `10-monitor.conf` would override any distro-provided `10-*.conf` in `/usr/share/`. This is intentional and correct behavior.

### Ubuntu Support Gap in `meta/main.yml`

The current `meta/main.yml` only lists ArchLinux as a supported platform. If adding Ubuntu testing via Vagrant, `meta/main.yml` should be updated:

```yaml
platforms:
  - name: ArchLinux
    versions: [all]
  - name: Ubuntu
    versions: [all]
```

However, since the role only copies config files (no distro-specific logic), it already works on Ubuntu without code changes.

## 4. Shared Migration

### Files to Create: `molecule/shared/`

Move the converge and verify logic to `molecule/shared/` so Docker, Vagrant, and default scenarios all share the same test playbooks.

#### `molecule/shared/converge.yml`

The converge playbook must handle the `remote_src: true` requirement. The role expects source files at `xorg_source_dir` on the target host. For Docker/Vagrant, the converge playbook should use a `pre_tasks` block to create stub config files on the target, then override `xorg_source_dir` to point to the stub location.

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  pre_tasks:
    - name: Create stub dotfiles source directory
      ansible.builtin.file:
        path: /tmp/dotfiles/etc/X11/xorg.conf.d
        state: directory
        mode: '0755'

    - name: Create stub 00-keyboard.conf
      ansible.builtin.copy:
        dest: /tmp/dotfiles/etc/X11/xorg.conf.d/00-keyboard.conf
        content: |
          # /etc/X11/xorg.conf.d/00-keyboard.conf
          Section "InputClass"
              Identifier "keyboard-layout"
              MatchIsKeyboard "on"
              Option "XkbLayout" "us,ru"
              Option "XkbOptions" "grp:ctrl_space_toggle"
          EndSection
        mode: '0644'

    - name: Create stub 10-monitor.conf
      ansible.builtin.copy:
        dest: /tmp/dotfiles/etc/X11/xorg.conf.d/10-monitor.conf
        content: |
          # /etc/X11/xorg.conf.d/10-monitor.conf
          Section "Monitor"
              Identifier "Monitor0"
              Option "PreferredMode" "2560x1440_60.00"
          EndSection
          Section "Device"
              Identifier "Card0"
              Driver "modesetting"
          EndSection
          Section "Screen"
              Identifier "Screen0"
              Device "Card0"
              Monitor "Monitor0"
              SubSection "Display"
                  Depth 24
                  Modes "2560x1440_60.00"
              EndSubSection
          EndSection
        mode: '0644'

  roles:
    - role: xorg
      vars:
        xorg_source_dir: /tmp/dotfiles
```

**Design decision: stub files vs volume mount.** Using stub files (inline `copy` content) in the converge playbook avoids:
- Docker volume mount path issues (Windows host paths vs Linux container paths)
- Vagrant synced folder setup complexity
- Dependency on the repository checkout being at a specific path on the controller

The tradeoff is that stub content may drift from the actual `dotfiles/` files. This is acceptable because the tests verify the role's file deployment mechanics, not the content of the specific config files. The verify step checks file existence, permissions, and key content markers.

**Alternative considered: mount `dotfiles/` as a Docker volume.** This would require `MOLECULE_PROJECT_DIRECTORY` to resolve to the repo root (not the role directory), and would not work cross-platform (Windows host paths). Rejected.

#### `molecule/shared/verify.yml`

See Section 7 for the full verify design.

### Default Scenario Update

After migration, `molecule/default/molecule.yml` should point to shared playbooks:

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

**Changes from current default:**
- Removed `vault_password_file` -- the xorg role uses no vault-encrypted variables. The current vault reference is a copy-paste artifact.
- Removed `vars_files` from converge/verify playbooks -- same reason.
- Added `ANSIBLE_ROLES_PATH` for consistency with other roles.
- Playbook paths changed to `../shared/`.

**Localhost note:** The shared converge creates stub files in `/tmp/dotfiles`. On localhost, the role could alternatively use the real `dotfiles/` directory. However, using stubs ensures test consistency across all scenarios and removes the dependency on `REPO_ROOT` being set.

## 5. Docker Scenario

### `molecule/docker/molecule.yml`

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
- No `prepare:` playbook reference -- the shared converge handles stub file creation in `pre_tasks`. If a prepare step is needed (e.g., pacman cache update), it can be added later.
- No vault configuration -- role uses no encrypted variables.
- `skip-tags: report` -- skips debug report task noise.
- `tmpfs: [/run, /tmp]` -- the shared converge creates stubs in `/tmp/dotfiles`. These are in tmpfs but this is fine because converge and verify run in the same container lifecycle.

**systemd requirement:** The xorg role does not manage any services, so systemd is not strictly required. However, using the systemd image maintains consistency with the project's Docker testing pattern and ensures `gather_facts` works reliably.

### Docker Prepare (optional)

No `molecule/docker/prepare.yml` is needed. The role does not install packages, so no `pacman -Sy` cache update is required. The shared converge `pre_tasks` handle all setup.

If a prepare step is later needed (e.g., if the role starts installing `xorg-server`), create:

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
- Memory 2048 MB is generous for a role that only copies config files. Could be reduced to 1024 MB, but 2048 maintains consistency with other roles.
- Ubuntu platform included even though `meta/main.yml` only lists ArchLinux. The role's tasks are distro-agnostic (file copy), so it works on Ubuntu without changes.

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

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**Why each task exists:**

1. **Bootstrap Python on Arch** -- `generic/arch` box may lack Python. `raw` module does not require Python on the target. `|| true` makes it a no-op on Ubuntu.
2. **Gather facts** -- needed for `os_family` conditionals in subsequent tasks.
3. **Refresh pacman keyring** -- `generic/arch` boxes ship with stale PGP keys. Temporarily disabling `SigLevel` allows the keyring package to be updated.
4. **Update apt cache** -- standard Ubuntu preparation. The xorg role does not install packages, but future extensions might. Including this keeps the prepare step forward-compatible.

**Not included:**
- Full system upgrade on Arch (`pacman -Syu`) -- not needed because the role only copies files. No library compatibility issues.
- Package installation -- the role does not install packages.

## 7. Verify.yml Design

### `molecule/shared/verify.yml`

```yaml
---
- name: Verify xorg role (config file assertions)
  hosts: all
  become: true
  gather_facts: true

  tasks:

    # ---- Directory exists ----

    - name: Stat /etc/X11/xorg.conf.d/
      ansible.builtin.stat:
        path: /etc/X11/xorg.conf.d
      register: xorg_verify_confdir

    - name: Assert /etc/X11/xorg.conf.d/ exists and is a directory
      ansible.builtin.assert:
        that:
          - xorg_verify_confdir.stat.exists
          - xorg_verify_confdir.stat.isdir
          - xorg_verify_confdir.stat.pw_name == 'root'
          - xorg_verify_confdir.stat.gr_name == 'root'
          - xorg_verify_confdir.stat.mode == '0755'
        fail_msg: "/etc/X11/xorg.conf.d/ missing or wrong permissions (expected root:root 0755)"

    # ---- 00-keyboard.conf ----

    - name: Stat /etc/X11/xorg.conf.d/00-keyboard.conf
      ansible.builtin.stat:
        path: /etc/X11/xorg.conf.d/00-keyboard.conf
      register: xorg_verify_keyboard

    - name: Assert 00-keyboard.conf exists with correct permissions
      ansible.builtin.assert:
        that:
          - xorg_verify_keyboard.stat.exists
          - xorg_verify_keyboard.stat.isreg
          - xorg_verify_keyboard.stat.pw_name == 'root'
          - xorg_verify_keyboard.stat.gr_name == 'root'
          - xorg_verify_keyboard.stat.mode == '0644'
        fail_msg: "00-keyboard.conf missing or wrong permissions (expected root:root 0644)"

    - name: Read 00-keyboard.conf
      ansible.builtin.slurp:
        src: /etc/X11/xorg.conf.d/00-keyboard.conf
      register: xorg_verify_keyboard_raw

    - name: Set keyboard config text fact
      ansible.builtin.set_fact:
        xorg_verify_keyboard_text: "{{ xorg_verify_keyboard_raw.content | b64decode }}"

    - name: Assert keyboard config contains XkbLayout
      ansible.builtin.assert:
        that:
          - "'XkbLayout' in xorg_verify_keyboard_text"
          - "'us' in xorg_verify_keyboard_text"
        fail_msg: "00-keyboard.conf missing XkbLayout or 'us' layout"

    - name: Assert keyboard config contains InputClass section
      ansible.builtin.assert:
        that:
          - "'Section \"InputClass\"' in xorg_verify_keyboard_text"
          - "'EndSection' in xorg_verify_keyboard_text"
        fail_msg: "00-keyboard.conf missing Section/EndSection structure"

    # ---- 10-monitor.conf ----

    - name: Stat /etc/X11/xorg.conf.d/10-monitor.conf
      ansible.builtin.stat:
        path: /etc/X11/xorg.conf.d/10-monitor.conf
      register: xorg_verify_monitor

    - name: Assert 10-monitor.conf exists with correct permissions
      ansible.builtin.assert:
        that:
          - xorg_verify_monitor.stat.exists
          - xorg_verify_monitor.stat.isreg
          - xorg_verify_monitor.stat.pw_name == 'root'
          - xorg_verify_monitor.stat.gr_name == 'root'
          - xorg_verify_monitor.stat.mode == '0644'
        fail_msg: "10-monitor.conf missing or wrong permissions (expected root:root 0644)"

    - name: Read 10-monitor.conf
      ansible.builtin.slurp:
        src: /etc/X11/xorg.conf.d/10-monitor.conf
      register: xorg_verify_monitor_raw

    - name: Set monitor config text fact
      ansible.builtin.set_fact:
        xorg_verify_monitor_text: "{{ xorg_verify_monitor_raw.content | b64decode }}"

    - name: Assert monitor config contains Monitor section
      ansible.builtin.assert:
        that:
          - "'Section \"Monitor\"' in xorg_verify_monitor_text"
          - "'Monitor0' in xorg_verify_monitor_text"
        fail_msg: "10-monitor.conf missing Monitor section or Monitor0 identifier"

    - name: Assert monitor config contains Device section with modesetting
      ansible.builtin.assert:
        that:
          - "'Section \"Device\"' in xorg_verify_monitor_text"
          - "'modesetting' in xorg_verify_monitor_text"
        fail_msg: "10-monitor.conf missing Device section or modesetting driver"

    - name: Assert monitor config contains Screen section
      ansible.builtin.assert:
        that:
          - "'Section \"Screen\"' in xorg_verify_monitor_text"
          - "'Screen0' in xorg_verify_monitor_text"
        fail_msg: "10-monitor.conf missing Screen section or Screen0 identifier"

    # ---- File count matches expected ----

    - name: List files in /etc/X11/xorg.conf.d/
      ansible.builtin.find:
        paths: /etc/X11/xorg.conf.d
        file_type: file
      register: xorg_verify_file_list

    - name: Assert exactly 2 config files deployed
      ansible.builtin.assert:
        that:
          - xorg_verify_file_list.matched == 2
        fail_msg: >-
          Expected 2 files in /etc/X11/xorg.conf.d/, found {{ xorg_verify_file_list.matched }}.
          Files: {{ xorg_verify_file_list.files | map(attribute='path') | list }}

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Xorg verify passed: /etc/X11/xorg.conf.d/ exists (root:root 0755),
          00-keyboard.conf deployed (root:root 0644, XkbLayout present),
          10-monitor.conf deployed (root:root 0644, Monitor/Device/Screen sections present),
          file count matches expected (2).
```

### Verify Design Rationale

| Check | Purpose | Cross-platform? |
|-------|---------|-----------------|
| Directory stat | Verifies role creates the target directory | Yes -- `/etc/X11/xorg.conf.d/` is universal |
| Keyboard file stat | Existence + permissions | Yes |
| Keyboard content | XkbLayout present, Section structure valid | Yes -- Xorg config format is universal |
| Monitor file stat | Existence + permissions | Yes |
| Monitor content | Monitor/Device/Screen sections present, modesetting driver | Yes |
| File count | Catches unexpected extra files or missing files | Yes |

**Content checks are intentionally shallow.** The stubs in `converge.yml` contain simplified versions of the real config. The verify checks for structural markers (`Section`, `EndSection`, key identifiers) rather than exact content. This makes the tests resilient to minor content changes in the stubs or real dotfiles.

**No platform-specific guards needed.** All assertions use universal paths and Xorg config syntax. Neither Arch nor Ubuntu differences affect any check.

## 8. Implementation Order

1. **Fix the register name bug in `tasks/main.yml`** -- change `_xorg_source_stat` to `xorg_source_stat` on lines 14-15. Without this fix, converge will always fail on the assert task.

2. **Create `molecule/shared/` directory** and write:
   - `molecule/shared/converge.yml` -- per Section 4
   - `molecule/shared/verify.yml` -- per Section 7

3. **Update `molecule/default/molecule.yml`** -- point to shared playbooks, remove vault references. Per Section 4.

4. **Delete old local playbooks:**
   - `molecule/default/converge.yml` (replaced by shared)
   - `molecule/default/verify.yml` (replaced by shared)

5. **Test default scenario** (localhost):
   ```bash
   cd ansible/roles/xorg
   molecule test -s default
   ```

6. **Create `molecule/docker/` directory** and write:
   - `molecule/docker/molecule.yml` -- per Section 5

7. **Test Docker scenario:**
   ```bash
   cd ansible/roles/xorg
   molecule test -s docker
   ```

8. **Create `molecule/vagrant/` directory** and write:
   - `molecule/vagrant/molecule.yml` -- per Section 6
   - `molecule/vagrant/prepare.yml` -- per Section 6

9. **Test Vagrant scenario:**
   ```bash
   cd ansible/roles/xorg
   molecule create -s vagrant
   molecule converge -s vagrant
   molecule verify -s vagrant
   molecule destroy -s vagrant
   ```

10. **Run full Vagrant test sequence:**
    ```bash
    cd ansible/roles/xorg
    molecule test -s vagrant
    ```

11. **Update `meta/main.yml`** to include Ubuntu as a supported platform (optional, if Ubuntu testing passes).

12. **Commit** all new and modified files.

### Files Created/Modified Summary

| Action | Path |
|--------|------|
| **Fix** | `ansible/roles/xorg/tasks/main.yml` (lines 14-15: `_xorg_source_stat` -> `xorg_source_stat`) |
| **Create** | `ansible/roles/xorg/molecule/shared/converge.yml` |
| **Create** | `ansible/roles/xorg/molecule/shared/verify.yml` |
| **Modify** | `ansible/roles/xorg/molecule/default/molecule.yml` (point to shared, remove vault) |
| **Delete** | `ansible/roles/xorg/molecule/default/converge.yml` |
| **Delete** | `ansible/roles/xorg/molecule/default/verify.yml` |
| **Create** | `ansible/roles/xorg/molecule/docker/molecule.yml` |
| **Create** | `ansible/roles/xorg/molecule/vagrant/molecule.yml` |
| **Create** | `ansible/roles/xorg/molecule/vagrant/prepare.yml` |
| **Modify** (optional) | `ansible/roles/xorg/meta/main.yml` (add Ubuntu platform) |

## 9. Risks / Notes

### `remote_src: true` and Dotfiles Availability

The role's copy task uses `remote_src: true`, meaning source files must exist on the target host. The shared converge handles this by creating stub files in `/tmp/dotfiles` and overriding `xorg_source_dir`. This decouples tests from the repository's `dotfiles/` directory.

**Risk:** Stub file content may diverge from actual `dotfiles/etc/X11/xorg.conf.d/` content over time. This is acceptable because the tests verify deployment mechanics (file copy, permissions, directory creation), not config correctness.

**Mitigation:** Keep stub content structurally similar to real files. Verify checks use structural markers (`Section`, key identifiers), not exact content.

### Xorg Config Path Differences

| Path | Arch | Ubuntu | Who writes |
|------|------|--------|------------|
| `/etc/X11/xorg.conf.d/` | Admin overrides (this role) | Admin overrides (this role) | Admin/role |
| `/usr/share/X11/xorg.conf.d/` | Distro defaults (package-managed) | Distro defaults (package-managed) | Package manager |

Both distros use `/etc/X11/xorg.conf.d/` for admin-provided snippets. No path adaptation needed. The role writes to `/etc/X11/xorg.conf.d/` on all platforms.

**Note:** On Ubuntu, the `/etc/X11/xorg.conf.d/` directory may not exist by default (it is created by `xserver-xorg` package or manually). The role's "Create X11 config directories" task handles this.

### Idempotence

The role should be fully idempotent:
- `ansible.builtin.file` (directory creation) is idempotent.
- `ansible.builtin.copy` with `remote_src: true` is idempotent -- it compares checksums and reports `ok` (not `changed`) when content matches.

Expected idempotence result: zero changes on second converge run.

### Docker tmpfs and `/tmp/dotfiles`

The Docker scenario uses `tmpfs: [/run, /tmp]`. Stub files are created in `/tmp/dotfiles` during converge `pre_tasks`. Since converge and verify run within the same container lifecycle (no restart between them), the tmpfs content persists. However, if the test sequence is interrupted between converge and verify, stub files would be lost on container restart.

**Mitigation:** Use `/opt/dotfiles` instead of `/tmp/dotfiles` to avoid tmpfs. Or accept the risk since molecule's test sequence is atomic. The plan uses `/tmp/dotfiles` for consistency with the converge design above, but implementer may choose `/opt/dotfiles` if tmpfs issues arise.

### No Package Installation Testing

The role does not install xorg packages. If package installation is added in the future:
- Docker: add `pacman -Sy` in prepare step
- Vagrant Arch: pacman keyring refresh already in prepare
- Vagrant Ubuntu: add `apt install xserver-xorg xinit` or verify they are installed by the role
- Verify: add `package_facts` assertion for distro-specific package names

### Vault References Removed

The current default scenario references `vault.yml` and `vault-pass.sh`. The xorg role uses no vault-encrypted variables. These references are removed in the shared migration. If a future role version requires vault variables, they must be re-added to the scenario configs.

### File Count Assertion Fragility

The verify checks for exactly 2 files in `/etc/X11/xorg.conf.d/`. On a real system (Vagrant VM), other packages may drop config files into this directory (e.g., `40-libinput.conf` from `xf86-input-libinput` on Arch). This assertion would fail on Vagrant VMs where Xorg packages are pre-installed.

**Mitigation options:**
1. Change assertion from "exactly 2" to "at least 2" -- avoids false failures but is less precise.
2. Check for specific filenames only (already covered by individual stat checks) and remove the count assertion entirely.
3. Keep count assertion only for Docker (clean environment) and skip on Vagrant.

**Recommendation:** Remove the file count assertion entirely. The individual file stat checks (`00-keyboard.conf` exists, `10-monitor.conf` exists) are sufficient. The count check adds fragility without significant value.

### `generic/arch` Vagrant Box Stale Keys

This is a known issue across all Vagrant scenarios in this project. The prepare.yml includes the standard keyring refresh workaround (temporarily disable SigLevel, update keyring, re-enable SigLevel). This is documented in the project's Vagrant CI post-mortems.
