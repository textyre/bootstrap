# zen_browser: Molecule Testing Plan

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### What the role does

The `zen_browser` role (`ansible/roles/zen_browser/`) installs the Zen Browser from the AUR on Arch Linux:

1. **Platform assertion** -- fails if `os_family != Archlinux`.
2. **Pacman cache refresh** -- `community.general.pacman: update_cache: true`.
3. **Pre-flight checks** -- `which zen-browser` (already installed?), `yay --version` (AUR helper available?). Fails hard if yay is missing.
4. **SUDO_ASKPASS helper** -- creates a temporary `/tmp/.ansible_sudo_askpass_zen` script for non-interactive sudo during AUR build (only when `ansible_become_password` is defined and browser not yet installed).
5. **AUR install** -- `yay -S --needed --noconfirm zen-browser-bin` as `zen_browser_user`. Adds `/usr/bin/core_perl` to PATH (needed by `makepkg`). Skipped when already installed.
6. **Cleanup** -- removes the temporary SUDO_ASKPASS helper.
7. **Verification** -- `which zen-browser` (hard fail if missing after install).
8. **Default browser** -- `xdg-settings set default-web-browser zen.desktop` when `zen_browser_set_default: true` (requires DISPLAY).

### Key variables (defaults/main.yml)

| Variable | Default | Purpose |
|----------|---------|---------|
| `zen_browser_aur_package` | `zen-browser-bin` | AUR package name (binary, no compilation) |
| `zen_browser_user` | `SUDO_USER \| user_id` | Non-root user for yay/makepkg |
| `zen_browser_set_default` | `true` | Whether to set as default browser |
| `zen_browser_desktop_file` | `zen.desktop` | Desktop entry filename for xdg-settings |

### Supported platforms (meta/main.yml)

- ArchLinux only. No other platforms listed.

### Existing tests

Single `molecule/default/` scenario:
- **Driver:** `default` (localhost, unmanaged)
- **converge.yml:** Loads vault.yml, Arch-only pre_tasks assert, applies `zen_browser` role.
- **verify.yml:** Checks binary exists (`which zen-browser`), package installed (`pacman -Qi zen-browser-bin`), desktop file exists (`/usr/share/applications/zen.desktop`), default browser set (`xdg-settings get`).
- **test_sequence:** syntax, converge, verify (no idempotence, no destroy).
- **molecule.yml:** vault_password_file configured but role uses no vault variables.

### Bugs in current task file

Two variable name mismatches in `tasks/main.yml`:

1. **Line 73:** `changed_when` references `_zen_browser_install.stdout` but the `register` on line 72 sets `zen_browser_install` (no leading underscore). This means `changed_when` evaluates against an undefined variable, always resulting in `changed`.
2. **Line 116:** `when` condition references `_zen_browser_current_default.stdout` but the `register` on line 101 sets `zen_browser_current_default` (no leading underscore). This means the "set default browser" task always runs when `zen_browser_set_default` is true, regardless of whether the default is already set.

These bugs do not block molecule testing but should be fixed before or during the migration.

## 2. GUI Limitation

Zen Browser is a desktop GUI application (Firefox-based). It cannot be launched or functionally tested in CI environments (Docker containers, headless VMs):

- **No X11/Wayland** -- containers and Vagrant VMs do not have a display server.
- **No GPU** -- even if Xvfb were available, browser rendering would be nonfunctional.
- `xdg-settings` requires a running display session (DISPLAY env) and may fail or produce misleading results in headless environments.

### Testing scope

What CAN be tested:
- Binary exists at expected path (`/usr/bin/zen-browser`)
- Package is registered with pacman (`pacman -Qi zen-browser-bin`)
- Desktop entry file exists (`/usr/share/applications/zen.desktop`)
- Desktop entry file is valid (contains required keys)

What CANNOT be tested:
- Browser actually launches
- Default browser setting via `xdg-settings` (needs DISPLAY + running session)
- Profile creation, extension loading, rendering

The `zen_browser_set_default` tasks (lines 95-117) must be skipped in CI. This is best accomplished via a tag (`configure`) and `skip-tags` in molecule config, or by setting `zen_browser_set_default: false` in converge vars.

## 3. Cross-Platform Analysis

### Zen Browser availability by distribution

| Distribution | Installation method | Package name | Notes |
|-------------|-------------------|-------------|-------|
| Arch Linux | AUR via yay | `zen-browser-bin` | Binary repackage, no compilation. ~150 MB download. |
| Ubuntu | Not in apt repos | N/A | No official PPA. Upstream provides `.deb` download or Flatpak. |
| Fedora | Not in repos | N/A | Upstream provides `.rpm` download or Flatpak. |
| Generic | Flatpak / AppImage / tarball | `io.github.nickvdp.zen-browser` (Flatpak) | Manual install required. |

### Cross-platform feasibility

The role is **Arch-only by design**: it hard-asserts `os_family == Archlinux` on line 7-11 and uses `yay` (AUR helper) for installation. There is no cross-platform path in the current code.

**Decision: Vagrant scenario should be Arch-only.** Adding Ubuntu would require implementing an entirely new installation method (Flatpak, .deb download, or AppImage), which is out of scope for a testing plan. The role explicitly declares only ArchLinux in `meta/main.yml`.

### AUR build in Docker challenge

The `zen-browser-bin` AUR package is a binary repackage (it downloads a prebuilt tarball), so it does NOT require compilation toolchains like `gcc`/`make`. However:

1. **yay must be available** -- the zen_browser role depends on yay being installed first. The Docker container must either have yay pre-installed in the image or the converge must install it.
2. **Non-root user required** -- `makepkg` refuses to run as root. The role uses `become_user: zen_browser_user` which defaults to `SUDO_USER`. In Docker (running as root with no sudo), `SUDO_USER` is unset, so `zen_browser_user` falls back to `root`. This will cause `yay` to fail.
3. **Network access required** -- yay downloads the PKGBUILD and tarball from the internet during install.
4. **Package size** -- ~150 MB download + extraction. Slow in CI.

### Docker scenario viability assessment

Running the full AUR install in a Docker container is problematic because:
- A non-root user must exist for `makepkg`
- The yay role must run first (dependency chain: `yay` -> `zen_browser`)
- The download is large and slow

This matches the pattern of the existing `yay` role, which only has a `default` (localhost) scenario and no Docker scenario. AUR-dependent roles are inherently difficult to test in containers.

**Decision: The Docker scenario should install the yay dependency in `prepare.yml` and create a non-root test user, OR skip the actual AUR install and test only the role's logic gates (platform assertion, yay check, etc.).** The more practical approach is to run the full install and accept the longer test time, since `zen-browser-bin` is a binary package (no compilation).

## 4. Shared Migration

### File structure after migration

```
ansible/roles/zen_browser/molecule/
  shared/
    converge.yml      <-- NEW: role invocation, no vault, no arch assert
    verify.yml        <-- NEW: cross-scenario assertions (headless-safe)
  default/
    molecule.yml      <-- UPDATED: references ../shared/
    (converge.yml)    <-- DELETE
    (verify.yml)      <-- DELETE
  docker/
    molecule.yml      <-- NEW
    prepare.yml       <-- NEW (install yay + create non-root user)
  vagrant/
    molecule.yml      <-- NEW (Arch-only)
    prepare.yml       <-- NEW
```

### shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: zen_browser
      vars:
        zen_browser_set_default: false
```

Key decisions:
- **No `vars_files` for vault** -- role uses no vault variables. The current converge loads vault.yml unnecessarily.
- **No `pre_tasks` OS assertion** -- the role itself asserts `os_family == Archlinux` in `tasks/main.yml` line 7-11. Duplicating this in converge is redundant.
- **`zen_browser_set_default: false`** -- disables the `xdg-settings` tasks that require a display server. These cannot work in Docker or headless Vagrant.

### shared/verify.yml

See Section 7 for full design.

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

**No idempotence step.** The `yay -S --needed --noconfirm` command is inherently not idempotent in Ansible's sense -- it always runs as a `command` module (not a state-based module), and the `changed_when` logic has a bug (see Section 1). Even with the bug fixed, the `command` module plus `which` checks make clean idempotence unreliable. The yay role itself omits idempotence from its test sequence for the same reason.

### molecule/docker/prepare.yml

The prepare playbook must set up the yay AUR helper and a non-root user, since zen_browser depends on both:

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

    - name: Install base-devel and git (yay build dependencies)
      community.general.pacman:
        name:
          - base-devel
          - git
        state: present

    - name: Create non-root test user for AUR builds
      ansible.builtin.user:
        name: testuser
        create_home: true
        shell: /bin/bash

    - name: Grant testuser passwordless sudo
      ansible.builtin.copy:
        dest: /etc/sudoers.d/testuser
        content: "testuser ALL=(ALL) NOPASSWD: ALL"
        mode: "0440"
        validate: "visudo -cf %s"

    - name: Install yay from AUR
      become: true
      become_user: testuser
      ansible.builtin.shell: |
        cd /tmp
        git clone https://aur.archlinux.org/yay.git yay_build
        cd yay_build
        makepkg -si --noconfirm
        cd /tmp
        rm -rf yay_build
      args:
        executable: /bin/bash
        creates: /usr/bin/yay
```

Key decisions:
- **Creates `testuser`** -- the converge will need to override `zen_browser_user: testuser` since `SUDO_USER` is unset in Docker. This must be done in shared/converge.yml or as a provisioner inventory var.
- **Installs yay from source** -- cannot use the yay role itself (circular dependency concern, and prepare should be minimal). A simple `git clone + makepkg` is sufficient.
- **`creates: /usr/bin/yay`** -- makes the yay install idempotent across prepare reruns.

### Docker user context problem

In the Docker container, `SUDO_USER` is unset (everything runs as root). The role's `zen_browser_user` default resolves to `root`, which will cause `yay` to fail (`makepkg` cannot run as root).

**Solution:** Override `zen_browser_user` in the converge. Update shared/converge.yml to accept this via a variable, or set it in the Docker molecule.yml provisioner inventory:

```yaml
# In molecule/docker/molecule.yml, under provisioner:
provisioner:
  inventory:
    group_vars:
      all:
        zen_browser_user: testuser
```

This is the cleanest approach -- the shared converge stays generic, and the Docker scenario provides the user context.

## 6. Vagrant Scenario

### molecule/vagrant/molecule.yml

Arch-only (no Ubuntu -- see Section 3 for rationale):

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

**No Ubuntu platform.** The role is Arch-only by design. Adding Ubuntu would require implementing a new installation path (Flatpak/.deb), which is a feature change, not a testing concern.

**No idempotence step.** Same rationale as Docker scenario -- AUR `command`-based install is not reliably idempotent.

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

    - name: Install base-devel and git (yay build dependencies)
      community.general.pacman:
        name:
          - base-devel
          - git
          - go
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Create aur_builder user for yay
      ansible.builtin.user:
        name: aur_builder
        create_home: true
        shell: /usr/bin/nologin
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Grant aur_builder passwordless pacman
      ansible.builtin.copy:
        dest: /etc/sudoers.d/aur-builder
        content: "aur_builder ALL=(ALL) NOPASSWD: /usr/bin/pacman"
        mode: "0440"
        validate: "visudo -cf %s"
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Install yay from AUR
      become: true
      become_user: aur_builder
      ansible.builtin.shell: |
        cd /tmp
        git clone https://aur.archlinux.org/yay.git yay_build
        cd yay_build
        makepkg -si --noconfirm
        cd /tmp
        rm -rf yay_build
      args:
        executable: /bin/bash
        creates: /usr/bin/yay
      when: ansible_facts['os_family'] == 'Archlinux'
```

This follows the `package_manager/molecule/vagrant/prepare.yml` pattern for keyring refresh and system upgrade, then adds yay installation as a prerequisite. In the Vagrant VM, `SUDO_USER` will be `vagrant`, so `zen_browser_user` resolves correctly to a non-root user without override.

### Vagrant user context

Vagrant VMs run Molecule playbooks via SSH as root (with `become: true`). The `SUDO_USER` env var is typically set to `vagrant`. The role's `zen_browser_user` resolves to `vagrant`, which is a real non-root user with a home directory. The `yay -S` command runs as `vagrant`, which has sudo access via the default Vagrant sudoers config.

However, `vagrant` user needs sudo access for yay's internal pacman calls. The default Vagrant sudoers grants `vagrant ALL=(ALL) NOPASSWD: ALL`, so this works out of the box. No `ansible_become_password` is needed, so the SUDO_ASKPASS helper creation is skipped (the `when: ansible_become_password is defined` guard handles this).

## 7. Verify.yml Design

### Approach

The verify playbook must work in headless environments (Docker and Vagrant) where no display server is available. All `xdg-settings` checks are excluded. Focus on artifact presence.

### shared/verify.yml

```yaml
---
- name: Verify zen_browser role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "../../defaults/main.yml"

  tasks:

    # ---- Platform guard ----

    - name: Assert we are on Arch Linux
      ansible.builtin.assert:
        that: ansible_facts['os_family'] == 'Archlinux'
        fail_msg: "zen_browser verify requires Arch Linux"

    # ---- Binary exists ----

    - name: Check zen-browser binary exists
      ansible.builtin.command: which zen-browser
      register: _zen_verify_bin
      changed_when: false

    - name: Assert zen-browser binary is in PATH
      ansible.builtin.assert:
        that: _zen_verify_bin.rc == 0
        fail_msg: "zen-browser binary not found in PATH"

    - name: Assert zen-browser binary is at expected path
      ansible.builtin.assert:
        that: _zen_verify_bin.stdout == '/usr/bin/zen-browser'
        fail_msg: >-
          zen-browser found at '{{ _zen_verify_bin.stdout }}'
          but expected '/usr/bin/zen-browser'

    # ---- Package registered with pacman ----

    - name: Check zen-browser-bin package is installed
      ansible.builtin.command: "pacman -Qi {{ zen_browser_aur_package }}"
      register: _zen_verify_pkg
      changed_when: false

    - name: Assert package is registered with pacman
      ansible.builtin.assert:
        that: _zen_verify_pkg.rc == 0
        fail_msg: "{{ zen_browser_aur_package }} package not registered with pacman"

    # ---- Desktop entry file exists ----

    - name: Stat desktop entry file
      ansible.builtin.stat:
        path: "/usr/share/applications/{{ zen_browser_desktop_file }}"
      register: _zen_verify_desktop

    - name: Assert desktop entry file exists
      ansible.builtin.assert:
        that:
          - _zen_verify_desktop.stat.exists
          - _zen_verify_desktop.stat.isreg
        fail_msg: >-
          Desktop entry /usr/share/applications/{{ zen_browser_desktop_file }}
          does not exist

    # ---- Desktop entry file content ----

    - name: Read desktop entry file
      ansible.builtin.slurp:
        src: "/usr/share/applications/{{ zen_browser_desktop_file }}"
      register: _zen_verify_desktop_raw

    - name: Set desktop entry text fact
      ansible.builtin.set_fact:
        _zen_verify_desktop_text: "{{ _zen_verify_desktop_raw.content | b64decode }}"

    - name: Assert desktop entry contains required keys
      ansible.builtin.assert:
        that:
          - "'[Desktop Entry]' in _zen_verify_desktop_text"
          - "'Type=Application' in _zen_verify_desktop_text"
          - "'Exec=' in _zen_verify_desktop_text"
          - "'Name=' in _zen_verify_desktop_text"
        fail_msg: >-
          Desktop entry file is missing required keys
          ([Desktop Entry], Type, Exec, Name)

    # ---- SUDO_ASKPASS helper cleaned up ----

    - name: Stat temporary SUDO_ASKPASS helper
      ansible.builtin.stat:
        path: /tmp/.ansible_sudo_askpass_zen
      register: _zen_verify_askpass

    - name: Assert SUDO_ASKPASS helper was removed
      ansible.builtin.assert:
        that: not _zen_verify_askpass.stat.exists
        fail_msg: >-
          Temporary SUDO_ASKPASS helper /tmp/.ansible_sudo_askpass_zen
          was not cleaned up (security risk)

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg:
          - "All zen_browser checks passed!"
          - "zen-browser binary: {{ _zen_verify_bin.stdout }}"
          - "{{ zen_browser_aur_package }} package: installed"
          - "Desktop entry: /usr/share/applications/{{ zen_browser_desktop_file }}"
          - "SUDO_ASKPASS cleanup: verified"
```

### Assertion summary

| Check | What is asserted | Notes |
|-------|-----------------|-------|
| Binary exists | `which zen-browser` returns 0 | Core install verification |
| Binary path | stdout == `/usr/bin/zen-browser` | Ensures standard AUR install location |
| Package registered | `pacman -Qi zen-browser-bin` returns 0 | Confirms pacman tracks the package |
| Desktop entry exists | `/usr/share/applications/zen.desktop` is a regular file | GUI integration artifact |
| Desktop entry valid | Contains `[Desktop Entry]`, `Type=Application`, `Exec=`, `Name=` | Minimal .desktop spec compliance |
| SUDO_ASKPASS cleaned | `/tmp/.ansible_sudo_askpass_zen` does not exist | Security: no password helper left behind |

### What is NOT tested (and why)

- **Default browser setting** (`xdg-settings`) -- requires DISPLAY and running desktop session. Disabled via `zen_browser_set_default: false` in converge.
- **Browser launch** -- GUI application, no display server in CI.
- **Browser version** -- `zen-browser --version` may require display libs; fragile.
- **Profile directory** -- created on first launch, which cannot happen in CI.
- **Idempotence of install task** -- `command` module with `yay` is not state-based; `changed_when` has a bug (see Section 1).

## 8. Implementation Order

1. **Fix variable name bugs in `tasks/main.yml`** -- rename `_zen_browser_install` to `zen_browser_install` on line 73 and `_zen_browser_current_default` to `zen_browser_current_default` on line 116 (drop the leading underscores in the `changed_when`/`when` references to match the `register` names).
2. **Create `molecule/shared/converge.yml`** -- content from Section 4.
3. **Create `molecule/shared/verify.yml`** -- content from Section 7.
4. **Update `molecule/default/molecule.yml`** -- point playbooks to `../shared/`, remove `vault_password_file`, add `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"`.
5. **Delete `molecule/default/converge.yml`** -- replaced by shared.
6. **Delete `molecule/default/verify.yml`** -- replaced by shared.
7. **Create `molecule/docker/molecule.yml`** -- content from Section 5, including `zen_browser_user: testuser` inventory override.
8. **Create `molecule/docker/prepare.yml`** -- content from Section 5 (pacman cache, base-devel, testuser, yay install).
9. **Run `molecule test -s docker`** -- validate syntax, create, prepare, converge, verify, destroy.
10. **Create `molecule/vagrant/molecule.yml`** -- content from Section 6 (Arch-only).
11. **Create `molecule/vagrant/prepare.yml`** -- content from Section 6 (keyring refresh, sysupgrade, yay install).
12. **Run `molecule test -s vagrant`** -- validate on Arch VM.
13. **Fix any issues** discovered during test runs.

## 9. Risks and Notes

### AUR download size and CI time

`zen-browser-bin` is a binary repackage that downloads a ~150 MB tarball from GitHub releases. In Docker CI with limited bandwidth, this can take several minutes. The yay build in prepare.yml also downloads ~50 MB (Go toolchain for yay itself). Total: ~200 MB downloads per test run.

**Mitigation:** Accept the slow speed for correctness. There is no way to avoid the download short of pre-baking zen-browser into the Docker image, which defeats the purpose of testing the install role.

### AUR package availability

AUR packages can be orphaned, renamed, or removed without notice. `zen-browser-bin` is currently actively maintained but this is an external dependency.

**Mitigation:** If the AUR package disappears, the test will fail with a clear `yay` error. No special handling needed.

### Variable name bugs cause silent misbehavior

The two bugs in `tasks/main.yml` (Section 1) mean:
- The install task always reports `changed` even when zen-browser was already installed (cosmetic but breaks idempotence checking).
- The "set default browser" task always runs even when the default is already correct (causes unnecessary changes and breaks idempotence).

**Recommendation:** Fix these bugs as step 1 of implementation, before writing any molecule tests. The correct references are `zen_browser_install` (not `_zen_browser_install`) and `zen_browser_current_default` (not `_zen_browser_current_default`).

### Docker user context requires provisioner override

The shared converge sets `zen_browser_set_default: false` but does not override `zen_browser_user`. In Docker, the default `SUDO_USER | user_id` resolves to `root`, causing `yay` failure. The Docker `molecule.yml` must provide `zen_browser_user: testuser` via provisioner inventory vars.

In Vagrant, `SUDO_USER` is `vagrant`, so no override is needed.

### No idempotence testing

Both Docker and Vagrant scenarios omit the idempotence step. This is intentional:
- The `yay -S` command is executed via `ansible.builtin.command`, which is not inherently idempotent.
- The `which zen-browser` pre-check gates the install (skips if already present), but the `changed_when` bug means the install task always reports `changed`.
- Even with the bug fixed, Molecule's idempotence check expects zero changes, and the `pacman update_cache` task always reports `changed`.

**Recommendation:** After fixing the variable bugs and adding `changed_when: false` to the pacman cache refresh (or accepting its `changed`), idempotence could be reconsidered. For now, skip it.

### xdg-settings testing gap

The `zen_browser_set_default` functionality is completely untested in all molecule scenarios. This is an inherent limitation of headless CI. The only way to test it would be a manual test on a workstation with a running desktop session, or a VM with Xvfb and a minimal window manager -- both are out of scope for automated molecule testing.

### Vault dependency removal

The current `molecule/default/converge.yml` loads `vault.yml` with `vars_files`. The zen_browser role does not reference any vault variables (`ansible_become_password` is a connection-layer variable, not loaded from vault in this context). Removing the vault dependency from the shared converge simplifies the setup and eliminates the need for `vault_password_file` in molecule config.

### `common` role dependency

If the role uses a `common` role for report tasks (tagged `report`), the `skip-tags: report` in molecule config will skip those tasks. The `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"` makes all sibling roles resolvable. No issue expected.

## 10. Success Criteria

1. Variable name bugs in `tasks/main.yml` are fixed.
2. `molecule test -s default` passes (syntax, converge, verify) on localhost.
3. `molecule test -s docker` passes (syntax, create, prepare, converge, verify, destroy) on Arch systemd container.
4. `molecule test -s vagrant` passes (syntax, create, prepare, converge, verify, destroy) on Arch VM.
5. No playbook duplication between scenarios (all reference `../shared/`).
6. Verify assertions cover: binary exists at `/usr/bin/zen-browser`, pacman package registered, desktop entry exists with valid content, SUDO_ASKPASS helper cleaned up.
7. No vault dependency in shared playbooks.
8. `zen_browser_set_default` tasks are skipped in all CI scenarios.
