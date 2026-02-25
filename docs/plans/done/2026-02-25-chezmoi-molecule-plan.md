# Plan: chezmoi role -- Docker + Vagrant KVM molecule scenarios

**Date:** 2026-02-25
**Role:** `ansible/roles/chezmoi/`
**Status:** Draft

## 1. Current State

### What the Role Does

Execution pipeline: `resolve paths -> install -> validate source -> wallpapers -> init+apply`

1. **Resolve paths** (`tasks/main.yml:7-16`) -- uses `getent` to look up the target user's home directory from `/etc/passwd`. Sets `chezmoi_user_home` fact.
2. **Install** (`tasks/main.yml:20-32`) -- dispatches to OS-specific install tasks via `include_tasks: "install-{{ ansible_facts['os_family'] | lower }}.yml"`:
   - **Arch** (`install-archlinux.yml`) -- `community.general.pacman` when `chezmoi_install_method == 'pacman'`
   - **Debian** (`install-debian.yml`) -- always uses the official install script (`get.chezmoi.io`) to `~/.local/bin/chezmoi`
   - **Script fallback** (`main.yml:24-32`) -- also in main.yml, runs the official script when `chezmoi_install_method == 'script'` (alternative to pacman on Arch)
3. **Validate source** (`tasks/main.yml:36-48`) -- checks that `chezmoi_source_dir` exists and is a directory. **BUG: references `_chezmoi_source_stat` but registers as `chezmoi_source_stat`** (missing leading underscore -- assertion will always fail).
4. **Wallpapers** (`tasks/main.yml:52-77`) -- copies wallpapers from `chezmoi_source_dir/wallpapers/` to `~/.local/share/wallpapers/` if the source directory exists.
5. **Init + apply** (`tasks/main.yml:81-93`) -- runs `chezmoi init --source <dir> --promptChoice "Choose color theme=<theme>" --apply` as the target user. The `--promptChoice` flag provides non-interactive answers to `.chezmoi.toml.tmpl` prompts.
6. **Guard** (`tasks/main.yml:95-103`) -- checks for nested `.chezmoidata` directories (stale data from prior broken runs).
7. **Report** (`tasks/main.yml:105-111`) -- debug output (tagged `report`).

### Key Variables (defaults/main.yml)

| Variable | Default | Purpose |
|----------|---------|---------|
| `chezmoi_user` | `SUDO_USER` or `user_id` | Target user for install and init |
| `chezmoi_source_dir` | `dotfiles_base_dir` fallback to `$REPO_ROOT/dotfiles` | Path to dotfiles source tree |
| `chezmoi_install_method` | `pacman` | `pacman` or `script` |
| `chezmoi_theme_name` | `dracula` | Theme choice passed to `--promptChoice` |

### Dotfiles Source Structure

The `dotfiles/` directory at the repo root contains chezmoi-managed files:
- `.chezmoi.toml.tmpl` -- prompts for `theme_name` (dracula or monochrome)
- `.chezmoidata/` -- TOML data files (themes.toml, fonts.toml, layout.toml, etc.)
- `.chezmoiscripts/` -- post-apply scripts (run_after_90_generate-layout-constants.sh.tmpl)
- `.chezmoiignore` -- ignore rules
- `dot_config/` -- templated config files (i3, ewwii, picom, rofi, alacritty, dunst, starship, gtk-3.0)
- `dot_xinitrc`, `dot_bashrc.tmpl`, `dot_zshrc.tmpl`, `dot_local/` -- home directory dotfiles
- `wallpapers/` -- wallpaper images

### Existing Test Scenario

| Scenario | Driver | Platforms | Prepare | Converge | Verify |
|----------|--------|-----------|---------|----------|--------|
| `default` | default (localhost) | Localhost only | none | molecule/default/converge.yml | molecule/default/verify.yml |

No Docker or Vagrant scenarios exist. Tests are not in `shared/`.

### Current converge.yml

- Asserts `os_family == 'Archlinux'` (Arch-only guard)
- Loads `vault.yml` via `vars_files` (but **vault.yml does not exist** at the referenced path)
- Applies the `chezmoi` role

### Current verify.yml

Checks 11 things after converge:
1. `which chezmoi` succeeds
2. `~/.xinitrc` exists
3. `~/.config/i3/config` exists
4. `~/.config/picom.conf` exists
5. `~/.config/ewwii/ewwii.rhai` exists
6. `~/.config/rofi/config.rasi` exists
7. `~/.config/alacritty/alacritty.toml` exists
8. `~/.config/dunst/dunstrc` exists
9. `~/.config/starship.toml` exists
10. `~/.local/bin/theme-switch` exists and is executable
11. `~/.local/share/wallpapers/` directory exists
12. `~/.config/gtk-3.0/settings.ini` exists

All checks use `ansible.builtin.stat` with `failed_when`. Also loads `vault.yml` (nonexistent) and `defaults/main.yml`.

### Known Bugs in Role Code

**BUG-01: `_chezmoi_source_stat` vs `chezmoi_source_stat`**
- `tasks/main.yml:39` registers `chezmoi_source_stat` (no leading underscore)
- `tasks/main.yml:45-46` asserts on `_chezmoi_source_stat` (with leading underscore)
- This means the assertion always fails because `_chezmoi_source_stat` is undefined
- The role probably works in production only because it runs from the real localhost where `REPO_ROOT` is set and the assertion failure is masked or the code has been updated in production

**BUG-02: vault.yml reference in converge/verify**
- Both converge.yml and verify.yml reference `inventory/group_vars/all/vault.yml`
- This file does not exist in the repository
- The chezmoi role does not use any vault-encrypted variables
- The `vars_files` reference should be removed

## 2. Cross-Platform Analysis

### chezmoi Installation

| Aspect | Arch Linux | Ubuntu/Debian |
|--------|-----------|---------------|
| Package manager install | `pacman -S chezmoi` (in community repo) | Not in standard apt repos |
| Script install | `get.chezmoi.io` -> `~/.local/bin/chezmoi` | `get.chezmoi.io` -> `~/.local/bin/chezmoi` |
| Binary location (pacman) | `/usr/bin/chezmoi` | N/A |
| Binary location (script) | `~/.local/bin/chezmoi` | `~/.local/bin/chezmoi` |
| Dependencies | None (static Go binary) | `curl` (for script download) |

### chezmoi init + apply Behavior

| Aspect | Arch | Ubuntu | Impact |
|--------|------|--------|--------|
| `chezmoi init --source` | Works | Works | Identical behavior |
| `--promptChoice` flag | Works | Works | Identical behavior |
| `.chezmoiscripts/` | Runs post-apply scripts | Runs post-apply scripts | Scripts may assume Arch packages (i3, ewwii, etc.) -- will fail on Ubuntu if target packages missing |
| Template rendering | `.tmpl` files rendered via Go templates | Same | Identical |
| `wallpapers/` copy | Works | Works | Pure file copy, no OS dependency |

### Key Cross-Platform Concern: Dotfiles Content is Arch-Specific

The dotfiles contain configs for Arch-specific packages: i3wm, ewwii, picom, rofi, alacritty, dunst. On Ubuntu:
- `chezmoi init --apply` will render and place all files (chezmoi itself is OS-agnostic)
- The files will exist at the correct paths
- But the **applications** these files configure will not be installed
- `.chezmoiscripts/run_after_90_generate-layout-constants.sh.tmpl` may fail if it depends on Arch-only tools

**Testing implication:** On Ubuntu, we can only verify that chezmoi installs and runs. We cannot verify that all 11 dotfiles from verify.yml are deployed, because `chezmoi apply` may fail or skip files when run in an environment where the dotfiles source references Arch-specific paths or tools.

### Install Method Per Platform

| Platform | Recommended `chezmoi_install_method` | Reason |
|----------|--------------------------------------|--------|
| Arch (Docker) | `pacman` | Standard. Package in community repo. |
| Arch (Vagrant) | `pacman` | Same. |
| Ubuntu (Vagrant) | `script` | chezmoi not in apt repos. Role's `install-debian.yml` already uses script method. |

The `install-debian.yml` task file ignores the `chezmoi_install_method` variable -- it always uses the script. The `install-archlinux.yml` only runs when `chezmoi_install_method == 'pacman'`. The fallback script task in `main.yml` runs when `chezmoi_install_method == 'script'`.

## 3. Shared Migration

### Files to Move

| Source | Destination |
|--------|-------------|
| `molecule/default/converge.yml` | `molecule/shared/converge.yml` (rewritten) |
| `molecule/default/verify.yml` | `molecule/shared/verify.yml` (rewritten) |

### Changes to `molecule/default/molecule.yml`

Update playbook paths to point to shared:
```yaml
playbooks:
  converge: ../shared/converge.yml
  verify: ../shared/verify.yml
```

Remove `vault_password_file` from config_options (vault.yml does not exist and is not needed).

### New `molecule/shared/converge.yml`

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: chezmoi
```

**Changes from current:**
- Removed `vars_files` vault.yml reference (nonexistent, not needed)
- Removed Arch-only assertion (role should run on any supported OS)
- Role variables are provided by defaults/main.yml or overridden in molecule.yml provisioner vars

### New `molecule/shared/verify.yml`

The verify must be split into two tiers:

**Tier 1 -- Universal (all platforms):** chezmoi binary installed and functional
**Tier 2 -- Dotfiles deployed (Arch only):** specific config files exist after `chezmoi apply`

Tier 2 is Arch-only because the dotfiles source tree contains Arch-specific configs and post-apply scripts. On Ubuntu, `chezmoi apply` may partially succeed but produce different file layouts.

```yaml
---
- name: Verify chezmoi role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- Tier 1: chezmoi binary installed ----

    - name: Check chezmoi binary is available in PATH
      ansible.builtin.command: which chezmoi
      register: chezmoi_verify_which
      changed_when: false
      failed_when: chezmoi_verify_which.rc != 0

    - name: Check chezmoi --version works
      ansible.builtin.command: chezmoi --version
      register: chezmoi_verify_version
      changed_when: false
      failed_when: chezmoi_verify_version.rc != 0

    - name: Assert chezmoi version output is non-empty
      ansible.builtin.assert:
        that: chezmoi_verify_version.stdout | length > 0
        fail_msg: "chezmoi --version produced empty output"

    # ---- Resolve user home for file checks ----

    - name: Get user home directory
      ansible.builtin.getent:
        database: passwd
        key: "{{ chezmoi_user }}"

    - name: Set user home fact
      ansible.builtin.set_fact:
        chezmoi_verify_home: "{{ getent_passwd[chezmoi_user][4] }}"

    # ---- Tier 1: chezmoi source directory initialized ----

    - name: Check chezmoi source directory exists
      ansible.builtin.stat:
        path: "{{ chezmoi_verify_home }}/.local/share/chezmoi"
      register: chezmoi_verify_source_dir

    - name: Assert chezmoi source directory was initialized
      ansible.builtin.assert:
        that:
          - chezmoi_verify_source_dir.stat.exists
          - chezmoi_verify_source_dir.stat.isdir
        fail_msg: "chezmoi source directory not found at ~/.local/share/chezmoi"
      when: chezmoi_verify_has_dotfiles | default(false)

    # ---- Tier 2: Dotfiles deployed (Arch only, with real dotfiles source) ----

    - name: Tier 2 -- verify deployed dotfiles (Arch with full dotfiles source)
      when:
        - ansible_facts['os_family'] == 'Archlinux'
        - chezmoi_verify_full | default(false)
      block:
        - name: Check .xinitrc exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.xinitrc"
          register: chezmoi_verify_xinitrc
          failed_when: not chezmoi_verify_xinitrc.stat.exists

        - name: Check i3 config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/i3/config"
          register: chezmoi_verify_i3
          failed_when: not chezmoi_verify_i3.stat.exists

        - name: Check picom config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/picom.conf"
          register: chezmoi_verify_picom
          failed_when: not chezmoi_verify_picom.stat.exists

        - name: Check ewwii config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/ewwii/ewwii.rhai"
          register: chezmoi_verify_ewwii
          failed_when: not chezmoi_verify_ewwii.stat.exists

        - name: Check rofi config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/rofi/config.rasi"
          register: chezmoi_verify_rofi
          failed_when: not chezmoi_verify_rofi.stat.exists

        - name: Check alacritty config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/alacritty/alacritty.toml"
          register: chezmoi_verify_alacritty
          failed_when: not chezmoi_verify_alacritty.stat.exists

        - name: Check dunst config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/dunst/dunstrc"
          register: chezmoi_verify_dunst
          failed_when: not chezmoi_verify_dunst.stat.exists

        - name: Check starship config exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/starship.toml"
          register: chezmoi_verify_starship
          failed_when: not chezmoi_verify_starship.stat.exists

        - name: Check theme-switch is executable
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.local/bin/theme-switch"
          register: chezmoi_verify_theme_switch
          failed_when: >-
            not chezmoi_verify_theme_switch.stat.exists or
            not chezmoi_verify_theme_switch.stat.executable

        - name: Check wallpapers directory exists
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.local/share/wallpapers"
          register: chezmoi_verify_wallpapers
          failed_when: >-
            not chezmoi_verify_wallpapers.stat.exists or
            not chezmoi_verify_wallpapers.stat.isdir

        - name: Check GTK3 settings exist
          ansible.builtin.stat:
            path: "{{ chezmoi_verify_home }}/.config/gtk-3.0/settings.ini"
          register: chezmoi_verify_gtk3
          failed_when: not chezmoi_verify_gtk3.stat.exists

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          chezmoi verify passed: binary installed ({{ chezmoi_verify_which.stdout }}),
          version {{ chezmoi_verify_version.stdout | trim }}.
```

**Design decisions:**
- `chezmoi_verify_full` defaults to `false`. Only the `default` (localhost) scenario sets it to `true`, because only localhost has the real `dotfiles/` source tree available.
- `chezmoi_verify_has_dotfiles` controls whether the source-dir-initialized check runs. In Docker/Vagrant without the dotfiles repo, chezmoi installs but does not init.
- Tier 2 is gated on both `Archlinux` and `chezmoi_verify_full` to prevent failures on Ubuntu.

## 4. Docker Scenario

### The Problem: chezmoi Needs Dotfiles Source

The chezmoi role runs `chezmoi init --source <dir> --apply`. In Docker, the dotfiles directory must be volume-mounted into the container or the role must be tested in **install-only mode**.

**Option A: Volume-mount dotfiles/** -- mount `$REPO_ROOT/dotfiles` into the container. Requires the repo to be available on the Docker host (true in CI, true locally).

**Option B: Install-only test** -- override `chezmoi_source_dir` to skip the init+apply step. Only test that chezmoi installs correctly. Simpler, but less coverage.

**Recommendation: Option A** -- volume-mount the dotfiles directory. This tests the full pipeline including init+apply.

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
      - "${MOLECULE_PROJECT_DIRECTORY}/../../../dotfiles:/opt/dotfiles:ro"
    tmpfs: [/run, /tmp]
    privileged: true
    dns_servers: [8.8.8.8, 8.8.4.4]

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
      Archlinux-systemd:
        chezmoi_source_dir: /opt/dotfiles
        chezmoi_verify_has_dotfiles: true
        chezmoi_verify_full: true
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

**Notes:**
- Volume mount: `${MOLECULE_PROJECT_DIRECTORY}/../../../dotfiles` resolves to `<repo_root>/dotfiles`. The path is: `ansible/roles/chezmoi/molecule/docker/` -> 3 levels up -> repo root.
- `chezmoi_source_dir` overridden to `/opt/dotfiles` (the mount point inside the container).
- `chezmoi_verify_full: true` enables Tier 2 dotfile existence checks.
- **No idempotence step.** `chezmoi init --apply` uses `changed_when: chezmoi_apply.rc == 0` which always reports `changed`. This is a known role design issue (the task lacks proper idempotence detection). Running idempotence would fail on second converge.
- No vault config -- the role does not use vault variables.

### `molecule/docker/prepare.yml`

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

    - name: Ensure curl is installed (for script install method fallback)
      community.general.pacman:
        name: curl
        state: present
```

**Why each task:**
1. **Update pacman cache** -- the Docker image may have stale package DB. Required before any `pacman -S` operations.
2. **Ensure curl** -- needed if `chezmoi_install_method` is changed to `script`. The custom Arch image may not have curl. Defensive preparation.

## 5. Vagrant Scenario

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
  inventory:
    host_vars:
      arch-vm:
        chezmoi_install_method: pacman
      ubuntu-noble:
        chezmoi_install_method: script
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

**Notes:**
- No idempotence step (same reason as Docker -- `chezmoi init --apply` always reports changed).
- `chezmoi_install_method` explicitly set per platform: `pacman` for Arch, `script` for Ubuntu.
- No `chezmoi_verify_full` or `chezmoi_verify_has_dotfiles` set -- both default to `false`. Vagrant VMs do not have the dotfiles repo mounted by default.
- Without `chezmoi_source_dir` pointing to a real dotfiles tree, the role will fail at the "Assert chezmoi source directory exists" task. **This requires a converge-time workaround** -- see Section 5.1.

### 5.1 The dotfiles Source Problem in Vagrant

The role's `tasks/main.yml:42-48` asserts that `chezmoi_source_dir` exists. In Vagrant VMs, there is no dotfiles directory. Three approaches:

**Approach A: Synced folder** -- use Vagrant's `synced_folder` to mount the host's `dotfiles/` into the VM. molecule-vagrant supports this:
```yaml
platforms:
  - name: arch-vm
    box: generic/arch
    provider_raw_config_args:
      - "vm.synced_folder '../../../../dotfiles', '/opt/dotfiles', type: 'rsync'"
```
This is fragile (rsync timing, path resolution) and makes the test dependent on host filesystem layout.

**Approach B: Minimal fixture dotfiles** -- create a minimal `molecule/shared/fixtures/dotfiles/` directory with just enough content for chezmoi to init successfully (`.chezmoi.toml.tmpl` and one simple template file). Override `chezmoi_source_dir` to point to this fixture, copied to the VM in prepare.yml.

**Approach C: Install-only test** -- skip the init+apply tasks entirely by overriding variables or using tags. Only verify that chezmoi binary installs correctly on both platforms.

**Recommendation: Approach C for Vagrant.** The Vagrant scenario's primary value is testing cross-platform **installation** (pacman vs script). Full init+apply is better tested in Docker (with volume-mounted dotfiles) and the default (localhost) scenario. This avoids the complexity of syncing dotfiles into VMs.

To implement Approach C, the converge.yml needs a variable to skip init+apply. However, modifying the role to add a skip variable is a role code change, not just a test change. A simpler alternative: the role will fail at the "Assert chezmoi source directory exists" task when `chezmoi_source_dir` does not exist. We can provide a `chezmoi_source_dir` that points to a minimal fixture.

**Revised recommendation: Approach B (minimal fixture).** Create the fixture, copy it in prepare.yml, and override `chezmoi_source_dir`. This tests the full pipeline without requiring the real dotfiles tree.

### Minimal Fixture: `molecule/shared/fixtures/dotfiles/`

```
molecule/shared/fixtures/dotfiles/
  .chezmoi.toml.tmpl        -- minimal (no prompts or hardcoded theme)
  dot_chezmoi_test_marker    -- simple file to verify deployment
```

**`.chezmoi.toml.tmpl`** (fixture):
```
[data]
  theme_name = "dracula"
```

**`dot_chezmoi_test_marker`** (fixture):
```
chezmoi-molecule-test
```

After `chezmoi init --source /opt/dotfiles --apply`, the file `~/.chezmoi_test_marker` should exist.

But there is a complication: the role passes `--promptChoice "Choose color theme={{ chezmoi_theme_name }}"` to `chezmoi init`. The real `.chezmoi.toml.tmpl` uses `promptChoiceOnce` with specific choices. The fixture `.chezmoi.toml.tmpl` must either:
- Use `promptChoiceOnce` with the same prompt text ("Choose color theme") and choices, OR
- Not use any prompts (hardcode the value)

The fixture should hardcode the value to avoid prompt complexity:
```
[data]
  theme_name = "dracula"
```

When `--promptChoice` is passed for a prompt that does not exist in the template, chezmoi ignores it silently. So the fixture's hardcoded template + the role's `--promptChoice` flag = no conflict.

### Revised `molecule/vagrant/molecule.yml`

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
  inventory:
    host_vars:
      arch-vm:
        chezmoi_install_method: pacman
        chezmoi_source_dir: /opt/dotfiles
        chezmoi_verify_has_dotfiles: true
      ubuntu-noble:
        chezmoi_install_method: script
        chezmoi_source_dir: /opt/dotfiles
        chezmoi_verify_has_dotfiles: true
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

    - name: Full system upgrade on Arch
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Ensure curl is installed (Ubuntu -- needed for get.chezmoi.io)
      ansible.builtin.apt:
        name: curl
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    - name: Create dotfiles fixture directory
      ansible.builtin.file:
        path: /opt/dotfiles
        state: directory
        mode: '0755'

    - name: Deploy minimal .chezmoi.toml.tmpl fixture
      ansible.builtin.copy:
        dest: /opt/dotfiles/.chezmoi.toml.tmpl
        content: |
          [data]
            theme_name = "dracula"
        mode: '0644'

    - name: Deploy minimal test marker dotfile
      ansible.builtin.copy:
        dest: /opt/dotfiles/dot_chezmoi_test_marker
        content: "chezmoi-molecule-test\n"
        mode: '0644'
```

**Why each task:**
1. **Python bootstrap** -- `generic/arch` may lack Python. `raw` does not require Python.
2. **Gather facts** -- needed for `os_family` conditionals after Python bootstrap.
3. **Keyring refresh** -- stale PGP keys in `generic/arch` boxes prevent package installs.
4. **System upgrade** -- ensures pacman DB and packages are current (prevents partial upgrade breakage).
5. **apt cache update** -- standard Ubuntu preparation.
6. **curl on Ubuntu** -- the `get.chezmoi.io` script requires curl. `bento/ubuntu-24.04` likely has it, but this is a safety net.
7-9. **Dotfiles fixture** -- creates a minimal dotfiles source at `/opt/dotfiles` so `chezmoi init --source /opt/dotfiles --apply` succeeds. The fixture contains only a `.chezmoi.toml.tmpl` (hardcoded theme, no prompts) and a simple dotfile that chezmoi will deploy to `~/.chezmoi_test_marker`.

## 6. Verify.yml Design

### Assertions Summary

| # | Assertion | Tier | Platforms | Source |
|---|-----------|------|-----------|--------|
| 1 | `which chezmoi` succeeds | 1 (Universal) | All | New |
| 2 | `chezmoi --version` succeeds and non-empty | 1 (Universal) | All | New |
| 3 | `~/.local/share/chezmoi` dir exists | 1 (Universal) | All (when `chezmoi_verify_has_dotfiles`) | New |
| 4 | `~/.chezmoi_test_marker` exists | 1 (Universal) | All (when `chezmoi_verify_has_dotfiles`) | New (fixture-based) |
| 5-15 | Specific dotfiles exist (.xinitrc, i3, picom, etc.) | 2 (Full) | Arch only, when `chezmoi_verify_full` | Existing (from default/verify.yml) |

### Verify Variable Controls

| Variable | Default | Set by | Purpose |
|----------|---------|--------|---------|
| `chezmoi_verify_has_dotfiles` | `false` | molecule.yml host_vars | Enables source-dir and basic deployment checks |
| `chezmoi_verify_full` | `false` | molecule.yml host_vars | Enables full Arch-specific dotfile checks (Tier 2) |

### Per-Scenario Verify Behavior

| Scenario | `chezmoi_verify_has_dotfiles` | `chezmoi_verify_full` | What Gets Tested |
|----------|-------------------------------|----------------------|------------------|
| `default` (localhost) | `true` | `true` | Full: binary + all 11 dotfiles |
| `docker` (Arch container) | `true` | `true` | Full: binary + all 11 dotfiles (real dotfiles volume-mounted) |
| `vagrant` arch-vm | `true` | `false` | Install + fixture marker: binary + source dir + test marker |
| `vagrant` ubuntu-noble | `true` | `false` | Install + fixture marker: binary + source dir + test marker |

### Updated verify.yml (complete, incorporating fixture marker check)

Add this task after the "Assert chezmoi source directory was initialized" task:

```yaml
    - name: Check chezmoi deployed the test marker file
      ansible.builtin.stat:
        path: "{{ chezmoi_verify_home }}/.chezmoi_test_marker"
      register: chezmoi_verify_marker
      failed_when: not chezmoi_verify_marker.stat.exists
      when: chezmoi_verify_has_dotfiles | default(false)
```

This task runs for both Docker (with real dotfiles -- the marker will not exist since real dotfiles have no `dot_chezmoi_test_marker`) and Vagrant (with fixture). To handle this:
- For Docker: do NOT include the marker check. Docker uses real dotfiles which do not contain the fixture marker.
- For Vagrant: include the marker check.

**Revised approach:** Add a separate variable `chezmoi_verify_fixture` for fixture-based checks:

| Variable | Default | Scenarios |
|----------|---------|-----------|
| `chezmoi_verify_fixture` | `false` | Vagrant sets to `true` |

Or simpler: just check if the file exists without failing:
```yaml
    - name: Check fixture marker deployed (Vagrant fixture only)
      ansible.builtin.stat:
        path: "{{ chezmoi_verify_home }}/.chezmoi_test_marker"
      register: chezmoi_verify_marker
      when: chezmoi_verify_fixture | default(false)

    - name: Assert fixture marker exists
      ansible.builtin.assert:
        that: chezmoi_verify_marker.stat.exists
        fail_msg: "chezmoi did not deploy ~/.chezmoi_test_marker from fixture dotfiles"
      when: chezmoi_verify_fixture | default(false)
```

### Final Variable Matrix

| Scenario | `chezmoi_verify_has_dotfiles` | `chezmoi_verify_full` | `chezmoi_verify_fixture` |
|----------|-------------------------------|----------------------|--------------------------|
| `default` | `true` | `true` | `false` |
| `docker` | `true` | `true` | `false` |
| `vagrant` | `true` | `false` | `true` |

## 7. Implementation Order

1. **Fix BUG-01** in `ansible/roles/chezmoi/tasks/main.yml`: change `_chezmoi_source_stat` to `chezmoi_source_stat` on lines 45-46.

2. **Create `molecule/shared/` directory** at `ansible/roles/chezmoi/molecule/shared/`.

3. **Create `molecule/shared/converge.yml`** -- stripped-down version without vault.yml or Arch assertion (Section 3).

4. **Create `molecule/shared/verify.yml`** -- tiered verification with variable controls (Section 6).

5. **Update `molecule/default/molecule.yml`**:
   - Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
   - Remove vault references
   - Add `chezmoi_verify_full: true` and `chezmoi_verify_has_dotfiles: true` to host_vars

6. **Delete old files**: `molecule/default/converge.yml` and `molecule/default/verify.yml` (now in shared/).

7. **Create `molecule/docker/` directory** at `ansible/roles/chezmoi/molecule/docker/`.

8. **Create `molecule/docker/molecule.yml`** (Section 4).

9. **Create `molecule/docker/prepare.yml`** (Section 4).

10. **Create `molecule/vagrant/` directory** at `ansible/roles/chezmoi/molecule/vagrant/`.

11. **Create `molecule/vagrant/molecule.yml`** (Section 5, revised).

12. **Create `molecule/vagrant/prepare.yml`** (Section 5).

13. **Update `meta/main.yml`**: add Debian/Ubuntu to platforms list (the role supports Debian via `install-debian.yml`):
    ```yaml
    platforms:
      - name: ArchLinux
        versions: [all]
      - name: Debian
        versions: [all]
      - name: Ubuntu
        versions: [all]
    ```

14. **Test Docker scenario locally**:
    ```bash
    cd ansible/roles/chezmoi
    molecule create -s docker
    molecule converge -s docker
    molecule verify -s docker
    molecule destroy -s docker
    ```

15. **Test Vagrant scenario locally** (requires KVM/libvirt):
    ```bash
    cd ansible/roles/chezmoi
    molecule create -s vagrant
    molecule converge -s vagrant
    molecule verify -s vagrant
    molecule destroy -s vagrant
    ```

16. **Test default scenario** to confirm shared migration did not break it:
    ```bash
    cd ansible/roles/chezmoi
    molecule test -s default
    ```

17. **Commit** all new and modified files.

## 8. Risks / Notes

### Network Access for Binary Download

The Debian/Ubuntu install method (`get.chezmoi.io` script) requires internet access to download the chezmoi binary from GitHub releases. In CI:
- Docker containers have DNS configured (`dns_servers: [8.8.8.8, 8.8.4.4]`) and can reach the internet.
- Vagrant VMs have NAT networking by default and can reach the internet.
- If CI runs in an air-gapped environment, the script install will fail. Mitigation: pre-download the chezmoi binary in prepare.yml and place it at `~/.local/bin/chezmoi`.

### chezmoi init --apply Idempotence

`chezmoi init --apply` is NOT idempotent in Ansible's sense:
- The task uses `changed_when: chezmoi_apply.rc == 0`, meaning it always reports `changed` on success.
- Running `chezmoi init` a second time on an already-initialized source is safe (chezmoi handles re-init gracefully), but Ansible will report `changed`.
- **Consequence:** idempotence test step will fail. All three scenarios omit `idempotence` from the test sequence.
- **Future fix:** Change the task to check if `~/.local/share/chezmoi/.chezmoi.toml` already exists and skip init if so, or use `changed_when` logic that compares before/after state.

### .chezmoiscripts Execution in Docker/Vagrant

The `dotfiles/.chezmoiscripts/run_after_90_generate-layout-constants.sh.tmpl` runs after `chezmoi apply`. This script likely depends on tools (awk, sed, bash) that are available in both Arch and Ubuntu. However:
- If the script references Arch-specific paths or tools, it will fail on Ubuntu.
- In Docker (Arch-only), this is not a concern.
- In Vagrant with the minimal fixture, no `.chezmoiscripts/` exist, so nothing runs.
- In Vagrant with real dotfiles (if later changed to Approach A), this could be an issue on Ubuntu.

### The `_chezmoi_source_stat` Bug Impact

BUG-01 (`_chezmoi_source_stat` vs `chezmoi_source_stat`) means the assertion at line 45-46 references an undefined variable. Ansible behavior when asserting on an undefined variable:
- In Ansible 2.15+, `undefined_variable.stat.exists` evaluates to an error, and the assert fails with `AnsibleUndefinedVariable`.
- This means the current role code **cannot pass** the source validation step as written.
- This bug must be fixed before any molecule scenario can succeed. If the role works in production, it may be because:
  - A different version of the code is deployed (without the underscore)
  - The task is being skipped by tags in production
  - Ansible's behavior differs in the specific execution context

**Fix:** line 45: `_chezmoi_source_stat.stat.exists` -> `chezmoi_source_stat.stat.exists`; line 46: `_chezmoi_source_stat.stat.isdir` -> `chezmoi_source_stat.stat.isdir`.

### Vault References

The current `molecule/default/converge.yml` and `verify.yml` both load `vault.yml` via `vars_files`. This file does not exist. The shared converge/verify should NOT reference vault.yml. The chezmoi role uses no vault-encrypted variables (no secrets in defaults, no `!vault` references in system.yml).

### Docker Volume Mount Path Resolution

The Docker molecule.yml mounts `${MOLECULE_PROJECT_DIRECTORY}/../../../dotfiles:/opt/dotfiles:ro`. This resolves to:
```
ansible/roles/chezmoi/molecule/docker/../../../dotfiles
= ansible/roles/chezmoi/../../../dotfiles
= ansible/roles/../../../dotfiles
= ansible/../../../dotfiles  (WRONG -- this goes outside the repo)
```

Corrected path calculation:
```
MOLECULE_PROJECT_DIRECTORY = ansible/roles/chezmoi
../../../dotfiles = ansible/roles/chezmoi/../../../dotfiles
  = ansible/roles/../../dotfiles
  = ansible/../dotfiles
  = dotfiles  (CORRECT -- repo root)
```

Wait -- `MOLECULE_PROJECT_DIRECTORY` points to the **role root** (`ansible/roles/chezmoi`), not the molecule scenario directory. So:
```
${MOLECULE_PROJECT_DIRECTORY}/../../../dotfiles
= ansible/roles/chezmoi/../../../dotfiles
= dotfiles  (relative to repo root)
```

This is correct: 3 levels up from `ansible/roles/chezmoi` reaches the repo root, then into `dotfiles/`.

### Ubuntu: `~/.local/bin` Not in PATH

On Ubuntu, `chezmoi` installed via the script goes to `~/.local/bin/chezmoi`. The `which chezmoi` verification depends on `~/.local/bin` being in PATH. On `bento/ubuntu-24.04`:
- The default `.bashrc` includes `~/.local/bin` in PATH via `if [ -d "$HOME/.local/bin" ] ; then PATH="$HOME/.local/bin:$PATH" ; fi`
- But Ansible's `command` module does not source `.bashrc` (it uses a non-login, non-interactive shell)
- `which chezmoi` may fail even though the binary exists

**Mitigation options:**
1. Use `ansible.builtin.stat` on the expected path (`~/.local/bin/chezmoi`) instead of `which`
2. Use `ansible.builtin.command: "{{ chezmoi_verify_home }}/.local/bin/chezmoi --version"` with the full path
3. Add `~/.local/bin` to PATH in prepare.yml via `/etc/profile.d/` or `/etc/environment`

**Recommendation:** In verify.yml, replace the `which chezmoi` check with a two-pronged approach:
```yaml
    - name: Check chezmoi is in PATH or at known location
      ansible.builtin.shell: >
        which chezmoi 2>/dev/null ||
        test -x {{ chezmoi_verify_home }}/.local/bin/chezmoi
      register: chezmoi_verify_which
      changed_when: false
      failed_when: chezmoi_verify_which.rc != 0

    - name: Determine chezmoi binary path
      ansible.builtin.set_fact:
        chezmoi_verify_bin: >-
          {{ 'chezmoi' if (chezmoi_verify_which.stdout | default('') | trim) != ''
             else chezmoi_verify_home ~ '/.local/bin/chezmoi' }}
```

Then use `chezmoi_verify_bin` for the `--version` check.

### File Structure After Implementation

```
ansible/roles/chezmoi/
  defaults/main.yml
  meta/main.yml
  tasks/
    main.yml               (BUG-01 fixed)
    install-archlinux.yml
    install-debian.yml
  molecule/
    shared/
      converge.yml         (NEW -- universal, no vault, no OS assertion)
      verify.yml           (NEW -- tiered, variable-gated)
    default/
      molecule.yml         (MODIFIED -- points to shared/, adds verify vars)
    docker/
      molecule.yml         (NEW -- Arch systemd container, dotfiles volume)
      prepare.yml          (NEW -- pacman cache + curl)
    vagrant/
      molecule.yml         (NEW -- Arch + Ubuntu VMs, fixture dotfiles)
      prepare.yml          (NEW -- keyring, curl, fixture deployment)
```

Total new files: 6
Modified files: 2 (tasks/main.yml bugfix, molecule/default/molecule.yml)
Deleted files: 2 (molecule/default/converge.yml, molecule/default/verify.yml)
