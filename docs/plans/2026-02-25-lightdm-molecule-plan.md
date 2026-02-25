# LightDM Role: Molecule Testing Plan

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/lightdm/`

---

## 1. Current State

### What the role does

The `lightdm` role deploys LightDM display manager configuration on Arch Linux:

1. **Resolves dotfiles source directory** -- validates that `lightdm_source_dir` exists
2. **Creates config directories** -- ensures `/etc/lightdm/lightdm.conf.d/` exists
3. **Deploys two files** from the dotfiles repository (`remote_src: true`):
   - `/etc/lightdm/lightdm.conf.d/10-config.conf` (root:root 0644) -- sets `greeter-session=nody-greeter`, custom X server command, and resolution setup script
   - `/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh` (lightdm:lightdm 0755) -- bash script that uses `xrandr`/`cvt` to add a custom resolution mode and paints the X root window black
4. **Enables and starts** the `lightdm` service (guarded by `lightdm_enable_service`)
5. **Reports** deployed file count and service state (tagged `lightdm`, skippable via `report` tag)

**Platform support:** Arch Linux only (`meta/main.yml` lists only `ArchLinux`). Single `tasks/main.yml` with no distro-specific task files.

**No handlers directory.** No templates directory (uses `ansible.builtin.copy` with `remote_src: true`, not `ansible.builtin.template`).

### Config file content

`10-config.conf`:
```ini
[Seat:*]
greeter-session=nody-greeter
xserver-command=X -br
display-setup-script=/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh 2560 1440 60
```

`add-and-set-resolution.sh`:
- Takes width, height, refresh as arguments
- Uses `xrandr` and `cvt` to create and apply a custom mode
- Runs `xsetroot -solid "#000000"` to prevent gray flash
- Always exits 0 (required -- non-zero causes LightDM infinite restart loop)

### Existing variables (`defaults/main.yml`)

| Variable | Value | Note |
|----------|-------|------|
| `lightdm_source_dir` | `dotfiles_base_dir` fallback to `$REPO_ROOT/dotfiles` | Path to dotfiles tree |
| `lightdm_enable_service` | `true` | Controls `systemd` service enable+start |
| `lightdm_system_files` | List of 2 file mappings | src/dest/owner/group/mode per file |

### Existing tests

```
molecule/default/
  molecule.yml    -- default driver (localhost), vault, ANSIBLE_ROLES_PATH
  converge.yml    -- assert os_family==Archlinux, load vault, apply lightdm role
  verify.yml      -- 5 checks: config exists, config perms, script exists, script perms, service enabled
```

The default scenario runs on localhost with vault password file. Test sequence: syntax, converge, verify (no idempotence check).

**Gaps in current tests:**
- No Docker or Vagrant scenarios
- No idempotence check in test sequence
- Vault dependency in converge (the role has no vault variables; vault is unnecessary)
- Arch-only assertion in converge prevents cross-platform testing
- No package installation check (lightdm package itself)
- No content verification of deployed files
- Service check uses `ansible.builtin.service` in check_mode rather than `systemctl is-enabled`
- No cross-platform support

### Bug in tasks/main.yml

Line 14 references `_lightdm_source_stat` (prefixed with underscore) but line 8 registers `lightdm_source_stat` (no underscore). This is a **runtime bug** -- the assertion will fail with an undefined variable error. The correct variable name in the assertion should be `lightdm_source_stat` (matching the register).

---

## 2. Display Server Limitation

### The core problem

LightDM is a display manager -- it starts X11 or Wayland sessions. It requires:
- A physical or virtual GPU (`/dev/dri/*` or a framebuffer device)
- X11 server (`Xorg`) or `wlroots`-compatible compositor
- A configured greeter (`nody-greeter` in this role)

**In Docker containers:** No display server is available. `systemctl start lightdm` will fail because Xorg cannot open any display device. The service unit will enter a failed state.

**In Vagrant VMs:** Even with KVM/libvirt, the default `generic/arch` and `bento/ubuntu-24.04` boxes use serial console (no graphical console). `Xorg` is not installed. LightDM cannot start.

### Test scope

The testable surface is:
1. **Package installation** -- lightdm is installed
2. **Config file deployment** -- files exist at correct paths with correct ownership and permissions
3. **Config file content** -- deployed files match expected content
4. **Service enabled** -- the systemd unit is enabled (will start on next boot with a display)
5. **Service NOT started** -- explicitly skip starting the service in test environments

### Implementation approach

Override `lightdm_enable_service: false` in molecule host_vars. This prevents the `ansible.builtin.service` task from attempting `state: started`. The verify playbook will use `systemctl is-enabled` to confirm the unit is enabled, and will NOT assert that it is running.

Additionally, `skip-tags: service` in provisioner options provides a second layer of protection.

---

## 3. Cross-Platform Analysis

### LightDM on Arch vs Ubuntu

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| Package name | `lightdm` | `lightdm` |
| Greeter packages | `nody-greeter` (AUR), `lightdm-gtk-greeter` (pacman) | `lightdm-gtk-greeter` (apt), `slick-greeter` (apt) |
| Config directory | `/etc/lightdm/lightdm.conf.d/` | `/etc/lightdm/lightdm.conf.d/` |
| Service name | `lightdm.service` | `lightdm.service` |
| Service user/group | `lightdm:lightdm` | `lightdm:lightdm` |
| Package manager install | `community.general.pacman` | `ansible.builtin.apt` |
| `os_family` fact | `Archlinux` | `Debian` |

### Greeter availability

The role configures `greeter-session=nody-greeter` in `10-config.conf`. `nody-greeter` is an AUR package on Arch and is not available in Ubuntu repositories at all. For testing purposes, this does not matter -- the config file is deployed as-is regardless of whether the greeter is installed, and the service will not be started.

### Source directory dependency

The role copies files from `lightdm_source_dir` (the dotfiles tree) using `remote_src: true`. In Docker/Vagrant, this directory does not exist on the target host. The `prepare.yml` must either:
- Create the directory structure and seed the files, OR
- Override `lightdm_source_dir` to point to a test fixture path

**Recommended approach:** Create the expected directory structure and files in `prepare.yml`. This tests the role as-is without variable overrides that might mask bugs.

### What needs changing for Ubuntu support (out of scope)

The role currently has no distro-specific task files and does not install the lightdm package itself. For Ubuntu support, the role would need:
1. Add `install-archlinux.yml` and `install-debian.yml` task files
2. Add platform dispatch in `tasks/main.yml`
3. Handle different greeter package names
4. Add Ubuntu to `meta/main.yml`

This is **out of scope** for the testing plan. The Vagrant Ubuntu scenario tests config deployment only (package installed in `prepare.yml`).

---

## 4. Shared Migration

### Current structure (before)

```
molecule/
  default/
    molecule.yml     -- localhost, vault
    converge.yml     -- assert Arch, load vault, apply role
    verify.yml       -- 5 checks
```

### Target structure (after)

```
molecule/
  shared/
    converge.yml     -- clean: just apply role
    verify.yml       -- comprehensive cross-platform assertions
  default/
    molecule.yml     -- points to ../shared/*, no vault
  docker/
    molecule.yml     -- arch-systemd container, skip service start
    prepare.yml      -- pacman cache + create dotfiles fixture + install lightdm
  vagrant/
    molecule.yml     -- Arch + Ubuntu VMs, skip service start
    prepare.yml      -- cross-platform prep + create dotfiles fixture + install lightdm
```

### molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: lightdm
```

Changes from current `default/converge.yml`:
- **Removed** `vars_files` vault reference (role has no vault variables)
- **Removed** `os_family == Archlinux` assertion (testing both distros)

### molecule/shared/verify.yml

Full content designed in Section 7 below.

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
- **Removed** `vault_password_file` (not needed)
- **Changed** playbook paths to `../shared/`
- **Changed** `ANSIBLE_ROLES_PATH` from `roles` to `../` (consistent with other roles)
- **Added** `idempotence` to test sequence

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
  inventory:
    host_vars:
      Archlinux-systemd:
        lightdm_enable_service: false
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
- `skip-tags: report,service` -- skips the report debug task and provides tag-level guard for the service task
- `lightdm_enable_service: false` -- belt-and-suspenders: the `when: lightdm_enable_service` guard in `tasks/main.yml` prevents service start even if tags are not filtered
- No display server exists in the container, so service start would fail regardless

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

    - name: Install lightdm package
      community.general.pacman:
        name: lightdm
        state: present

    - name: Create dotfiles fixture directory
      ansible.builtin.file:
        path: /tmp/dotfiles/etc/lightdm/lightdm.conf.d
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Create fixture 10-config.conf
      ansible.builtin.copy:
        dest: /tmp/dotfiles/etc/lightdm/lightdm.conf.d/10-config.conf
        content: |
          [Seat:*]
          greeter-session=nody-greeter
          xserver-command=X -br
          display-setup-script=/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh 2560 1440 60
        owner: root
        group: root
        mode: '0644'

    - name: Create fixture add-and-set-resolution.sh
      ansible.builtin.copy:
        dest: /tmp/dotfiles/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
        content: |
          #!/bin/bash
          set -x
          x="$1"
          y="$2"
          freq="$3"
          if [ $# -ne 3 ]; then
          echo "Usage: $0 x y freq"
          exit 0
          fi
          output=$( xrandr | (grep -m1 ' connected primary' || grep -m1 ' connected') | cut -d' ' -f1 )
          mode=$( cvt "$x" "$y" "$freq" | grep -v '^#' | cut -d' ' -f3- )
          modename="${x}x${y}"
          xrandr --newmode $modename $mode
          xrandr --addmode "$output" "$modename"
          xrandr --output "$output" --mode "$modename"
          xsetroot -solid "#000000"
          exit 0
        owner: root
        group: root
        mode: '0755'

    - name: Set lightdm_source_dir to fixture path
      ansible.builtin.set_fact:
        lightdm_source_dir: /tmp/dotfiles
```

**Note:** The last task sets `lightdm_source_dir` as a host fact. However, `set_fact` in prepare.yml does not persist into converge.yml. The variable must be overridden in the molecule.yml `inventory.host_vars` instead. Updated molecule.yml host_vars:

```yaml
  inventory:
    host_vars:
      Archlinux-systemd:
        lightdm_enable_service: false
        lightdm_source_dir: /tmp/dotfiles
```

The `set_fact` task in prepare.yml should be **removed**. The fixture file creation is sufficient.

### What can be tested in Docker scenario

| Check | Possible | Note |
|-------|----------|------|
| lightdm package installed | Yes | Installed in prepare |
| `/etc/lightdm/lightdm.conf.d/10-config.conf` exists | Yes | Deployed by role |
| Config file permissions (root:root 0644) | Yes | |
| `/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh` exists | Yes | Deployed by role |
| Script permissions (lightdm:lightdm 0755) | Partial | `lightdm` user may not exist without full package setup; see Risks |
| Config content matches expected | Yes | slurp + assert |
| Script is executable | Yes | Mode check |
| lightdm.service enabled | Maybe | Unit file exists from package; `systemctl is-enabled` may work |
| lightdm.service running | No | No display server |

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
        lightdm_enable_service: false
        lightdm_source_dir: /tmp/dotfiles
      ubuntu-noble:
        lightdm_enable_service: false
        lightdm_source_dir: /tmp/dotfiles
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

    - name: Install lightdm on Arch
      community.general.pacman:
        name: lightdm
        state: present
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Install lightdm on Ubuntu
      ansible.builtin.apt:
        name:
          - lightdm
          - python3
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    # ---- Dotfiles fixture (both distros) ----

    - name: Create dotfiles fixture directory
      ansible.builtin.file:
        path: /tmp/dotfiles/etc/lightdm/lightdm.conf.d
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Create fixture 10-config.conf
      ansible.builtin.copy:
        dest: /tmp/dotfiles/etc/lightdm/lightdm.conf.d/10-config.conf
        content: |
          [Seat:*]
          greeter-session=nody-greeter
          xserver-command=X -br
          display-setup-script=/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh 2560 1440 60
        owner: root
        group: root
        mode: '0644'

    - name: Create fixture add-and-set-resolution.sh
      ansible.builtin.copy:
        dest: /tmp/dotfiles/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
        content: |
          #!/bin/bash
          set -x
          x="$1"
          y="$2"
          freq="$3"
          if [ $# -ne 3 ]; then
          echo "Usage: $0 x y freq"
          exit 0
          fi
          output=$( xrandr | (grep -m1 ' connected primary' || grep -m1 ' connected') | cut -d' ' -f1 )
          mode=$( cvt "$x" "$y" "$freq" | grep -v '^#' | cut -d' ' -f3- )
          modename="${x}x${y}"
          xrandr --newmode $modename $mode
          xrandr --addmode "$output" "$modename"
          xrandr --output "$output" --mode "$modename"
          xsetroot -solid "#000000"
          exit 0
        owner: root
        group: root
        mode: '0755'
```

### Display limitation in Vagrant

Even in a full VM, `generic/arch` and `bento/ubuntu-24.04` do not have Xorg or a virtual framebuffer installed. LightDM cannot start. The same `lightdm_enable_service: false` override is applied.

A theoretical option would be to install `xorg-server` + `xf86-video-vesa` in prepare.yml and start LightDM against a virtual framebuffer, but this would:
- Add significant complexity and install time (~200MB+ of X11 dependencies)
- Still fail without a real framebuffer device in KVM serial-only mode
- Test X11 / greeter functionality, which is outside the role's scope (the role deploys config, not the display stack)

**Conclusion:** Service start testing is not feasible or necessary. The role's job is to deploy configuration and enable the unit. Display server functionality is an integration concern.

---

## 7. Verify.yml Design

### molecule/shared/verify.yml

```yaml
---
- name: Verify LightDM role
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

    - name: Assert lightdm package is installed
      ansible.builtin.assert:
        that: "'lightdm' in ansible_facts.packages"
        fail_msg: "lightdm package not found"

    # ---- Config directory ----

    - name: Stat /etc/lightdm/lightdm.conf.d directory
      ansible.builtin.stat:
        path: /etc/lightdm/lightdm.conf.d
      register: lightdm_verify_confdir

    - name: Assert config directory exists
      ansible.builtin.assert:
        that:
          - lightdm_verify_confdir.stat.exists
          - lightdm_verify_confdir.stat.isdir
        fail_msg: "/etc/lightdm/lightdm.conf.d directory missing"

    # ---- 10-config.conf existence and permissions ----

    - name: Stat /etc/lightdm/lightdm.conf.d/10-config.conf
      ansible.builtin.stat:
        path: /etc/lightdm/lightdm.conf.d/10-config.conf
      register: lightdm_verify_config

    - name: Assert 10-config.conf exists with correct owner and mode
      ansible.builtin.assert:
        that:
          - lightdm_verify_config.stat.exists
          - lightdm_verify_config.stat.isreg
          - lightdm_verify_config.stat.pw_name == 'root'
          - lightdm_verify_config.stat.gr_name == 'root'
          - lightdm_verify_config.stat.mode == '0644'
        fail_msg: >-
          /etc/lightdm/lightdm.conf.d/10-config.conf missing or wrong permissions
          (expected root:root 0644, got {{ lightdm_verify_config.stat.pw_name | default('?') }}:{{ lightdm_verify_config.stat.gr_name | default('?') }} {{ lightdm_verify_config.stat.mode | default('?') }})

    # ---- 10-config.conf content ----

    - name: Read 10-config.conf content
      ansible.builtin.slurp:
        src: /etc/lightdm/lightdm.conf.d/10-config.conf
      register: lightdm_verify_config_raw

    - name: Set config text fact
      ansible.builtin.set_fact:
        lightdm_verify_config_text: "{{ lightdm_verify_config_raw.content | b64decode }}"

    - name: Assert config contains Seat section
      ansible.builtin.assert:
        that: "'[Seat:*]' in lightdm_verify_config_text"
        fail_msg: "'[Seat:*]' section header missing from 10-config.conf"

    - name: Assert config specifies greeter-session
      ansible.builtin.assert:
        that: "'greeter-session=' in lightdm_verify_config_text"
        fail_msg: "'greeter-session' directive missing from 10-config.conf"

    - name: Assert config specifies display-setup-script
      ansible.builtin.assert:
        that: "'display-setup-script=' in lightdm_verify_config_text"
        fail_msg: "'display-setup-script' directive missing from 10-config.conf"

    - name: Assert display-setup-script points to resolution script
      ansible.builtin.assert:
        that: "'add-and-set-resolution.sh' in lightdm_verify_config_text"
        fail_msg: "display-setup-script does not reference add-and-set-resolution.sh"

    # ---- add-and-set-resolution.sh existence and permissions ----

    - name: Stat add-and-set-resolution.sh
      ansible.builtin.stat:
        path: /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
      register: lightdm_verify_script

    - name: Assert resolution script exists and is executable
      ansible.builtin.assert:
        that:
          - lightdm_verify_script.stat.exists
          - lightdm_verify_script.stat.isreg
          - lightdm_verify_script.stat.mode == '0755'
        fail_msg: >-
          add-and-set-resolution.sh missing or not executable
          (expected mode 0755, got {{ lightdm_verify_script.stat.mode | default('?') }})

    - name: Assert resolution script ownership (lightdm:lightdm)
      ansible.builtin.assert:
        that:
          - lightdm_verify_script.stat.pw_name == 'lightdm'
          - lightdm_verify_script.stat.gr_name == 'lightdm'
        fail_msg: >-
          add-and-set-resolution.sh ownership wrong
          (expected lightdm:lightdm, got {{ lightdm_verify_script.stat.pw_name | default('?') }}:{{ lightdm_verify_script.stat.gr_name | default('?') }}).
          The lightdm user/group may not exist if the lightdm package was not properly installed.
      when: "'lightdm' in ansible_facts.packages"

    # ---- add-and-set-resolution.sh content ----

    - name: Read resolution script content
      ansible.builtin.slurp:
        src: /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
      register: lightdm_verify_script_raw

    - name: Set script text fact
      ansible.builtin.set_fact:
        lightdm_verify_script_text: "{{ lightdm_verify_script_raw.content | b64decode }}"

    - name: Assert script has bash shebang
      ansible.builtin.assert:
        that: "lightdm_verify_script_text is match('#!/bin/bash')"
        fail_msg: "Resolution script missing #!/bin/bash shebang"

    - name: Assert script uses xrandr
      ansible.builtin.assert:
        that: "'xrandr' in lightdm_verify_script_text"
        fail_msg: "Resolution script does not contain xrandr commands"

    - name: Assert script always exits 0 (prevents LightDM restart loop)
      ansible.builtin.assert:
        that: "'exit 0' in lightdm_verify_script_text"
        fail_msg: >-
          Resolution script does not contain 'exit 0'.
          Non-zero exit causes LightDM infinite restart loop.

    # ---- Service state (enabled only, NOT running) ----

    - name: Check lightdm service is enabled
      ansible.builtin.command: systemctl is-enabled lightdm.service
      register: lightdm_verify_svc_enabled
      changed_when: false
      failed_when: false

    - name: Assert lightdm service is enabled
      ansible.builtin.assert:
        that: lightdm_verify_svc_enabled.stdout == 'enabled'
        fail_msg: >-
          lightdm.service is not enabled (got '{{ lightdm_verify_svc_enabled.stdout }}').
          Note: the service is expected to be enabled but NOT running in test environments
          (no display server available).
      when: lightdm_enable_service | default(true)

    - name: Verify lightdm service is NOT running (expected in headless test)
      ansible.builtin.command: systemctl is-active lightdm.service
      register: lightdm_verify_svc_active
      changed_when: false
      failed_when: false

    - name: Confirm service inactive is expected
      ansible.builtin.debug:
        msg: >-
          lightdm.service is '{{ lightdm_verify_svc_active.stdout }}' -- this is expected.
          LightDM requires a display server (X11/Wayland) which is not available in test environments.

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          LightDM role verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}.
          Config files deployed: 10-config.conf (root:root 0644),
          add-and-set-resolution.sh (0755).
          Service enabled: {{ lightdm_verify_svc_enabled.stdout | default('unknown') }}.
          Service running: {{ lightdm_verify_svc_active.stdout | default('unknown') }} (expected: inactive).
```

### Assertion summary table

| # | Assertion | Docker | Vagrant | When guard |
|---|-----------|--------|---------|------------|
| 1 | lightdm package installed | Yes | Yes | always |
| 2 | `/etc/lightdm/lightdm.conf.d/` directory exists | Yes | Yes | always |
| 3 | `10-config.conf` exists, root:root 0644 | Yes | Yes | always |
| 4 | Config contains `[Seat:*]` | Yes | Yes | always |
| 5 | Config contains `greeter-session=` | Yes | Yes | always |
| 6 | Config contains `display-setup-script=` | Yes | Yes | always |
| 7 | Config references `add-and-set-resolution.sh` | Yes | Yes | always |
| 8 | Script exists and is executable (0755) | Yes | Yes | always |
| 9 | Script owned by lightdm:lightdm | Yes | Yes | `lightdm in packages` |
| 10 | Script has bash shebang | Yes | Yes | always |
| 11 | Script uses xrandr | Yes | Yes | always |
| 12 | Script contains `exit 0` (safety) | Yes | Yes | always |
| 13 | Service enabled | Yes | Yes | `lightdm_enable_service` |
| 14 | Service inactive (informational) | Yes | Yes | always (debug, no assertion) |

The service enabled check (#13) depends on how the package is installed and whether the unit file exists. In Docker and Vagrant, the package is installed in `prepare.yml`, so the unit file should be present. However, if `lightdm_enable_service` is `false` (as set in host_vars), the role will not enable the service. This creates a conflict: we want the service enabled for verification, but we do not want the role to attempt starting it.

**Resolution:** The role's service task does both `enabled: true` and `state: started` in one `ansible.builtin.service` call, guarded by `when: lightdm_enable_service`. If we set `lightdm_enable_service: false`, neither enable nor start happens. The verify check for "service enabled" should therefore be guarded by `when: lightdm_enable_service | default(true)`, which will skip it when the variable is false. This is the correct behavior -- in test environments, we accept that the service is not enabled because we explicitly disabled it.

Alternatively, the role's `tasks/main.yml` could be refactored to separate enable from start (e.g., always enable, conditionally start). This is a role improvement, not a testing concern, and is out of scope.

---

## 8. Implementation Order

### Step 1: Fix the variable name bug in tasks/main.yml

1. In `ansible/roles/lightdm/tasks/main.yml` line 14, change `_lightdm_source_stat` to `lightdm_source_stat` (remove the underscore prefix). This is a runtime bug that would cause the role to fail.

### Step 2: Create shared directory and playbooks

2. Create `ansible/roles/lightdm/molecule/shared/` directory
3. Create `molecule/shared/converge.yml` (clean, no vault, no Arch assertion)
4. Create `molecule/shared/verify.yml` (comprehensive, as designed in Section 7)

### Step 3: Migrate default scenario

5. Update `molecule/default/molecule.yml` to reference `../shared/converge.yml` and `../shared/verify.yml`
6. Remove `vault_password_file`, update `ANSIBLE_ROLES_PATH`, add `idempotence` to test sequence
7. Delete `molecule/default/converge.yml`
8. Delete `molecule/default/verify.yml`
9. Test: `molecule syntax -s default`

### Step 4: Create Docker scenario

10. Create `ansible/roles/lightdm/molecule/docker/` directory
11. Create `molecule/docker/molecule.yml` (per Section 5)
12. Create `molecule/docker/prepare.yml` (per Section 5 -- pacman cache, install lightdm, create dotfiles fixture)
13. Test: `molecule test -s docker`

### Step 5: Create Vagrant scenario

14. Create `ansible/roles/lightdm/molecule/vagrant/` directory
15. Create `molecule/vagrant/molecule.yml` (per Section 6)
16. Create `molecule/vagrant/prepare.yml` (per Section 6 -- Python bootstrap, keyring refresh, install lightdm, create dotfiles fixture)
17. Test: `molecule test -s vagrant`

### Step 6: Validate idempotence

18. Confirm `molecule test -s docker` passes idempotence (no changed tasks on second run)
19. Confirm `molecule test -s vagrant` passes idempotence on both platforms
20. If idempotence fails, investigate whether the `ansible.builtin.copy` task with `remote_src: true` reports changed due to attribute differences

### Step 7: Commit

21. Stage all new/changed files
22. Commit: `feat(lightdm): add molecule docker + vagrant scenarios with shared verify`

---

## 9. Risks / Notes

### Display server -- testing boundary

LightDM cannot be fully tested without a display server. This is a fundamental limitation, not a gap in the testing plan. The role's value is in deploying correct configuration. Whether LightDM successfully starts X11 and a greeter is an integration concern outside the role's scope.

If full integration testing is ever needed, options include:
- `Xvfb` (X Virtual Framebuffer) installed in prepare.yml -- allows Xorg to run without hardware
- QEMU VM with VGA device (`-vga std`) -- provides a real framebuffer
- Neither option is worth the complexity for config deployment testing.

### Dotfiles fixture in prepare.yml

The role uses `ansible.builtin.copy` with `remote_src: true`, meaning it copies files that must already exist on the target host. In production, these files come from the dotfiles repository cloned to the host. In tests, `prepare.yml` creates fixture files at `/tmp/dotfiles/`.

**Risk:** If the fixture content drifts from the actual dotfiles content, the test becomes less meaningful. The content assertions in verify.yml check structural properties (`[Seat:*]`, `greeter-session=`, `exit 0`) rather than exact content, so minor drifts are tolerated.

**Alternative considered:** Mount the actual `dotfiles/` directory into the Docker container via volumes. This was rejected because:
- It couples the test to the host filesystem layout
- Vagrant VMs cannot easily mount Windows host paths
- The role's behavior is the same regardless of file content (it copies whatever is in the source)

### lightdm user/group ownership

The role deploys `add-and-set-resolution.sh` with `owner: lightdm, group: lightdm`. The `lightdm` user and group are created by the lightdm package during installation. If the package is installed in `prepare.yml` (as planned), the user/group should exist before the role runs.

**Risk on Ubuntu:** On Ubuntu, the `lightdm` package installation triggers `dpkg-reconfigure` which may attempt to configure a default display manager. This could hang on interactive prompts. Mitigation: set `DEBIAN_FRONTEND=noninteractive` in the prepare task environment.

Updated Ubuntu install task for prepare.yml:
```yaml
    - name: Install lightdm on Ubuntu (non-interactive)
      ansible.builtin.apt:
        name:
          - lightdm
          - python3
        state: present
      environment:
        DEBIAN_FRONTEND: noninteractive
      when: ansible_facts['os_family'] == 'Debian'
```

### Idempotence with remote_src copy

The `ansible.builtin.copy` module with `remote_src: true` compares the source and destination files. If both exist and are identical (content, owner, group, mode), the task reports `ok`. On second run, this should be idempotent.

**Potential issue:** The `lightdm_source_dir` stat + assert task at the top of `tasks/main.yml` always runs and always returns `ok` (stat is read-only). No idempotence concern there.

### Autologin configuration in test environments

The current `10-config.conf` does NOT configure autologin (no `autologin-user=` directive). This is safe for test environments. If autologin were configured, it would be irrelevant in headless test environments since the service is not started.

### nody-greeter dependency

The config specifies `greeter-session=nody-greeter`. This package is in the AUR (Arch) and unavailable on Ubuntu. The test does NOT install nody-greeter because:
- It is not needed for config deployment testing
- It is an AUR package requiring `yay` or `makepkg` (complex, slow)
- The role itself does not install it (out of scope for this role)

The verify.yml checks that `greeter-session=` is present in the config but does not assert a specific greeter name, keeping the test flexible.

### Variable name bug (tasks/main.yml line 14)

The assertion references `_lightdm_source_stat` but the register on line 8 stores `lightdm_source_stat`. This will cause an `undefined variable` error at runtime. This must be fixed before testing can proceed. It is listed as Step 1 in the Implementation Order.

---

## File tree after implementation

```
ansible/roles/lightdm/
  defaults/main.yml              (unchanged)
  meta/main.yml                  (unchanged -- Arch-only for now)
  tasks/main.yml                 (BUGFIX: line 14 variable name)
  templates/                     (empty, unchanged)
  molecule/
    shared/
      converge.yml               (NEW -- clean role application)
      verify.yml                 (NEW -- 14 assertions, cross-platform safe)
    default/
      molecule.yml               (UPDATED -- point to shared/, remove vault, add idempotence)
      converge.yml               (DELETED)
      verify.yml                 (DELETED)
    docker/
      molecule.yml               (NEW -- arch-systemd, service disabled)
      prepare.yml                (NEW -- pacman update, install lightdm, create dotfiles fixture)
    vagrant/
      molecule.yml               (NEW -- Arch + Ubuntu, service disabled)
      prepare.yml                (NEW -- cross-platform prep, install lightdm, create dotfiles fixture)
```
