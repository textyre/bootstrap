# Plan: packages role -- Molecule testing (shared + docker + vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/packages/`

---

## 1. Current State

### What the role does

The `packages` role installs workstation packages via OS-native package managers:

- **System upgrade** (Arch only): runs `pacman -Syu` before package installs
- **Build combined list**: aggregates 16 category lists (`packages_base`, `packages_editors`, `packages_docker`, `packages_xorg`, `packages_wm`, `packages_filemanager`, `packages_network`, `packages_media`, `packages_desktop`, `packages_graphics`, `packages_session`, `packages_terminal`, `packages_fonts`, `packages_theming`, `packages_search`, `packages_viewers`) plus `packages_distro[os_family]` into a single `packages_all` fact
- **OS dispatch**: includes `install-archlinux.yml` or `install-debian.yml` based on `ansible_facts['os_family'] | lower`
  - Arch: `community.general.pacman` with `update_cache: true`
  - Debian: `ansible.builtin.apt` with `update_cache: true`, `cache_valid_time: 3600`
- **Report**: debug message with total count (tagged `report`)

**Variables** (`defaults/main.yml`): all 16 category lists default to `[]`; `packages_distro` defaults to `{}`. Actual package names are defined in `ansible/inventory/group_vars/all/packages.yml` (87 Arch-specific packages across all categories).

**OS support declared** (`meta/main.yml`): ArchLinux, Debian. No dependencies.

### What tests exist now

Single `molecule/default/` scenario:

- **Driver:** `default` (localhost, `managed: false`)
- **Provisioner:** Ansible with vault password, local connection. Provides a minimal test package set inline in `molecule.yml` (`git`, `curl`, `vim`, `jq`, plus `base-devel`/`build-essential` via `packages_distro`)
- **converge.yml:** Loads `vault.yml`, applies `packages` role. The vault dependency exists but is unlikely to be needed (no vault variables in the role itself).
- **verify.yml:** Builds `packages_all` from the inline variables, then loops with `pacman -Q` (Arch) or `dpkg -l` (Debian) to verify each package is installed.
- **Test sequence:** `dependency` -> `syntax` -> `converge` -> `idempotence` -> `verify`. No `create`/`destroy` (localhost driver).

**Gaps in current tests:**

- Vault dependency in converge.yml is unnecessary (role has no vault variables)
- No Docker or Vagrant scenarios -- only runs on localhost
- verify.yml re-implements the `packages_all` aggregation from `tasks/main.yml` (duplication)
- No `package_facts`-based verification (uses shell commands instead)
- No cross-platform execution -- only runs on whatever OS the developer happens to be on
- Idempotence test is good but may be slow due to the full upgrade step on Arch

---

## 2. Cross-Platform Analysis

### How the role handles Arch vs Ubuntu

The role dispatches to OS-specific task files:

| Aspect | Arch (`install-archlinux.yml`) | Debian (`install-debian.yml`) |
|---|---|---|
| Module | `community.general.pacman` | `ansible.builtin.apt` |
| Cache update | `update_cache: true` | `update_cache: true`, `cache_valid_time: 3600` |
| System upgrade | Yes (`pacman -Syu` in `main.yml`) | No |
| Package list | `packages_all` (single flat list) | `packages_all` (single flat list) |

### Package name differences

The production `packages.yml` is almost entirely Arch-specific. Most package names do NOT map 1:1 to Debian:

| Category | Arch packages | Debian equivalent | Notes |
|---|---|---|---|
| `packages_base` | `git`, `curl`, `htop`, `tmux`, `unzip`, `rsync` | Same names | Cross-platform safe |
| `packages_base` | `openssh`, `nftables`, `cronie`, `sqlite` | `openssh-server`, `nftables`, `cron`, `sqlite3` | Names differ |
| `packages_base` | `chezmoi` | Not in apt repos | AUR/binary install only |
| `packages_editors` | `vim`, `neovim` | `vim`, `neovim` | Cross-platform safe |
| `packages_docker` | `docker`, `docker-compose` | `docker.io`, `docker-compose` | Names differ |
| `packages_xorg` | `xorg`, `xorg-apps`, `xorg-xinit`, `xorg-drivers` | `xorg`, `x11-apps`, `xinit`, `xserver-xorg-video-all` | Names differ significantly |
| `packages_fonts` | `ttf-jetbrains-mono-nerd`, etc. | Not in apt repos | Arch-specific Nerd Font packaging |
| `packages_viewers` | `bat`, `jq` | `bat`, `jq` | Cross-platform safe |
| `packages_search` | `fzf`, `ripgrep` | `fzf`, `ripgrep` | Cross-platform safe |
| `packages_distro` | `base-devel`, `pacman-contrib`, `perl` | `build-essential` | By design, already handled |

**Key insight:** the production `packages.yml` only defines Arch package names. For Molecule testing, the converge must supply a curated subset of packages that exist on both distros, or use `packages_distro` to provide distro-specific overrides.

### Test package strategy

For cross-platform testing, use a minimal set of packages known to exist under the same name on both Arch and Debian/Ubuntu:

**Cross-platform safe (same package name):**
- `git`, `curl`, `htop`, `tmux`, `unzip`, `rsync`, `vim`, `jq`, `fzf`

**Distro-specific via `packages_distro`:**
- Arch: `base-devel`
- Debian: `build-essential`

This is what the current `molecule/default/molecule.yml` already does, minus `htop`, `tmux`, `unzip`, `rsync`, `fzf`. The test set should be expanded slightly to exercise more of the aggregation logic (multiple non-empty category lists).

---

## 3. Shared Migration

Move the current `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/`, with modifications:

### `molecule/shared/converge.yml`

Based on ntp pattern -- simple, no vault:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: packages
```

**Changes from current default/converge.yml:**
- Removes `vars_files` vault loading (role has no vault variables)
- Package variable overrides move to each scenario's `molecule.yml` provisioner block

### `molecule/shared/verify.yml`

Redesigned to use `package_facts` instead of raw shell commands. See section 6.

### `molecule/default/molecule.yml`

Updated to reference shared playbooks:

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
    skip-tags: report
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
    group_vars:
      all:
        packages_base: [git, curl]
        packages_editors: [vim]
        packages_docker: []
        packages_xorg: []
        packages_wm: []
        packages_filemanager: []
        packages_network: []
        packages_media: []
        packages_desktop: []
        packages_graphics: []
        packages_session: []
        packages_terminal: []
        packages_fonts: []
        packages_theming: []
        packages_search: []
        packages_viewers: [jq]
        packages_distro:
          Archlinux: [base-devel]
          Debian: [build-essential]
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

**Changes:**
- Removes vault dependency entirely
- Removes galaxy dependency block
- Adds `skip-tags: report`
- Points converge/verify to `../shared/`
- Keeps inline package variable overrides (localhost scenario still useful for quick local dev testing)

---

## 4. Docker Scenario

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
  inventory:
    group_vars:
      all:
        packages_base: [git, curl, htop, tmux, unzip, rsync]
        packages_editors: [vim]
        packages_docker: []
        packages_xorg: []
        packages_wm: []
        packages_filemanager: []
        packages_network: []
        packages_media: []
        packages_desktop: []
        packages_graphics: []
        packages_session: []
        packages_terminal: []
        packages_fonts: []
        packages_theming: []
        packages_search: [fzf, ripgrep]
        packages_viewers: [jq]
        packages_distro:
          Archlinux: [base-devel]
          Debian: [build-essential]
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
- Docker scenario is Arch-only (no Debian systemd container available in this project)
- DNS servers added to ensure `pacman -Syu` can resolve mirrors inside the container
- Package list larger than localhost scenario to exercise more categories, but still lightweight (no xorg/fonts/desktop packages that would bloat the container)
- `packages_docker`, `packages_xorg`, `packages_wm`, etc. all set to `[]` to avoid installing heavy packages in a container
- `skip-tags: report` suppresses the debug output

### `molecule/docker/prepare.yml`

Follow existing ntp/package_manager docker prepare pattern:

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

**Why:** the arch-systemd image may have a stale package cache. The prepare step ensures `pacman -Syu` in the converge step does not fail on 404s for moved packages.

---

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
    group_vars:
      all:
        packages_base: [git, curl, htop, tmux, unzip, rsync]
        packages_editors: [vim]
        packages_docker: []
        packages_xorg: []
        packages_wm: []
        packages_filemanager: []
        packages_network: []
        packages_media: []
        packages_desktop: []
        packages_graphics: []
        packages_session: []
        packages_terminal: []
        packages_fonts: []
        packages_theming: []
        packages_search: [fzf]
        packages_viewers: [jq]
        packages_distro:
          Archlinux: [base-devel]
          Debian: [build-essential]
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
- Two platforms: Arch (generic/arch) + Ubuntu (bento/ubuntu-24.04) -- true cross-platform test
- `ripgrep` excluded from vagrant test set: on Ubuntu 24.04, the package name is `ripgrep` and exists in the repos, but older Ubuntu versions may not have it. `fzf` is universally available.
- All category lists that contain Arch-specific package names are emptied (`packages_xorg: []`, etc.)
- `packages_distro` provides the only distro-specific packages (`base-devel` vs `build-essential`)

### `molecule/vagrant/prepare.yml`

Follow the established package_manager vagrant prepare pattern:

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

**This is an exact copy of the package_manager vagrant prepare.** The `generic/arch` Vagrant box has known issues:
1. No Python pre-installed (needs raw bootstrap)
2. Stale pacman keyring (needs keyring refresh with temporary SigLevel override)
3. Stale packages that can cause SSL/openssl incompatibilities (needs full upgrade)

---

## 6. verify.yml Design

### Approach: `package_facts` + assert

The verify should not re-implement the `packages_all` aggregation from `tasks/main.yml`. Instead, it should:

1. Use `ansible.builtin.package_facts` to gather installed packages
2. Build the `packages_all` list (this duplication is unavoidable since verify runs as a separate playbook without access to role-set facts)
3. Assert each package appears in `ansible_facts.packages`

`package_facts` is preferred over shell commands because:
- It works cross-platform (auto-detects package manager)
- It returns structured data (version, source) rather than requiring output parsing
- It is idempotent and does not produce `changed` noise

### `molecule/shared/verify.yml`

```yaml
---
- name: Verify packages role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "../../defaults/main.yml"

  tasks:

    # ---- Build expected package list ----

    - name: Build combined package list (mirrors tasks/main.yml logic)
      ansible.builtin.set_fact:
        packages_verify_expected: >-
          {{ packages_base
             + packages_editors
             + packages_docker
             + packages_xorg
             + packages_wm
             + packages_filemanager
             + packages_network
             + packages_media
             + packages_desktop
             + packages_graphics
             + packages_session
             + packages_terminal
             + packages_fonts
             + packages_theming
             + packages_search
             + packages_viewers
             + (packages_distro[ansible_facts['os_family']] | default([])) }}

    # ---- Gather package facts ----

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    # ---- Assert all expected packages are installed ----

    - name: Assert each expected package is installed
      ansible.builtin.assert:
        that: "item in ansible_facts.packages"
        fail_msg: "Package '{{ item }}' not found in installed packages"
        quiet: true
      loop: "{{ packages_verify_expected }}"
      loop_control:
        label: "{{ item }}"

    # ---- Verify idempotence hint: no pending actions ----

    - name: Verify package install is idempotent (Arch)
      community.general.pacman:
        name: "{{ packages_verify_expected }}"
        state: present
      check_mode: true
      register: packages_verify_idem_arch
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Assert pacman install reports no changes
      ansible.builtin.assert:
        that: not packages_verify_idem_arch.changed
        fail_msg: "pacman would still install packages -- converge was not idempotent"
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Verify package install is idempotent (Debian)
      ansible.builtin.apt:
        name: "{{ packages_verify_expected }}"
        state: present
      check_mode: true
      register: packages_verify_idem_deb
      when: ansible_facts['os_family'] == 'Debian'

    - name: Assert apt install reports no changes
      ansible.builtin.assert:
        that: not packages_verify_idem_deb.changed
        fail_msg: "apt would still install packages -- converge was not idempotent"
      when: ansible_facts['os_family'] == 'Debian'

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          packages verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}:
          all {{ packages_verify_expected | length }} packages present and idempotent.
```

### Design decisions

1. **`vars_files: ../../defaults/main.yml`**: loads the role's defaults so that any category list not overridden by the scenario's `molecule.yml` group_vars defaults to `[]`. This is the pattern established by `package_manager/molecule/shared/verify.yml`.

2. **`packages_verify_expected`** (not `packages_all`): uses the `_verify_` prefix naming convention from the ntp role (`ntp_verify_conf`, `ntp_verify_logdir`, etc.) to avoid colliding with the `packages_all` fact set during converge.

3. **`package_facts` with `manager: auto`**: detects pacman on Arch, apt/dpkg on Debian automatically. The resulting `ansible_facts.packages` dict is keyed by package name.

4. **Check-mode idempotence assertion**: runs the install module in `check_mode: true` and asserts `not changed`. This catches edge cases where `package_facts` reports a package as installed but the module would still do work (e.g., version pinning differences). This is a supplement to the idempotence step in the test sequence, not a replacement.

5. **`quiet: true` on the loop assertion**: suppresses per-item success output, keeping the verify log clean when 10+ packages are checked.

---

## 7. Implementation Order

### Step 1: Create `molecule/shared/` directory and files

```
ansible/roles/packages/molecule/shared/converge.yml
ansible/roles/packages/molecule/shared/verify.yml
```

Write both files as specified in sections 3 and 6.

### Step 2: Update `molecule/default/molecule.yml`

- Remove vault dependency from provisioner
- Remove galaxy dependency block
- Add `skip-tags: report`
- Point `converge:` and `verify:` to `../shared/converge.yml` and `../shared/verify.yml`
- Add `ANSIBLE_ROLES_PATH` env
- Remove `ANSIBLE_VERBOSITY` (not needed; use `-v` flag when desired)
- Simplify test_sequence (remove `dependency`, `create_sequence`, `check_sequence`, `converge_sequence`, `destroy_sequence`)

### Step 3: Delete old converge/verify from default

Remove:
```
ansible/roles/packages/molecule/default/converge.yml
ansible/roles/packages/molecule/default/verify.yml
```

These are replaced by the shared versions.

### Step 4: Create `molecule/docker/` directory and files

```
ansible/roles/packages/molecule/docker/molecule.yml
ansible/roles/packages/molecule/docker/prepare.yml
```

Write both files as specified in section 4.

### Step 5: Create `molecule/vagrant/` directory and files

```
ansible/roles/packages/molecule/vagrant/molecule.yml
ansible/roles/packages/molecule/vagrant/prepare.yml
```

Write both files as specified in section 5.

### Step 6: Test docker scenario locally

```bash
cd ansible/roles/packages
molecule test -s docker
```

Expected: syntax check passes, container created, prepare updates cache, converge installs ~10 packages, idempotence passes (no changes on second run), verify asserts all packages present, container destroyed.

### Step 7: Test vagrant scenario locally

```bash
cd ansible/roles/packages
molecule test -s vagrant
```

Expected: two VMs created (arch-vm, ubuntu-noble), prepare bootstraps Python + refreshes keyring (Arch) / updates apt cache (Ubuntu), converge installs packages on both, idempotence passes on both, verify asserts packages present on both, VMs destroyed.

### Step 8: Test default scenario

```bash
cd ansible/roles/packages
molecule test -s default
```

Expected: runs on localhost with minimal package set, all assertions pass.

### Step 9: Lint check

```bash
cd ansible
ansible-lint roles/packages/
```

Ensure no new lint warnings from the molecule files.

---

## 8. Risks / Notes

### Large package installs in CI

- **Mitigation:** test package sets are deliberately small (10-15 packages). The production `packages.yml` lists 87+ packages including Xorg, fonts, desktop tools -- none of those are included in test scenarios.
- **Docker scenario:** fastest. Container already has base Arch packages; adding ~10 lightweight CLI tools takes <30 seconds.
- **Vagrant scenario:** slowest. VM boot (~60s) + pacman keyring refresh (~30s) + full system upgrade (~120s) + package install (~30s). Total: ~4-5 minutes per platform, ~10 minutes for both.

### Idempotence and the `pacman -Syu` upgrade step

- The role runs `pacman -Syu` (full system upgrade) on every converge. This is tagged `upgrade` and always reports `changed` if any system package was updated.
- **Impact on idempotence test:** the second converge run during `idempotence` will likely report `changed` because `pacman -Syu` always checks for updates. This is a known issue.
- **Mitigation options:**
  1. Tag the upgrade task and add `upgrade` to `skip-tags` in molecule scenarios (recommended)
  2. Accept that idempotence will show `changed: 1` for the upgrade task and configure `molecule.yml` accordingly
  3. The upgrade task already has `tags: ['install', 'upgrade']`, so adding `skip-tags: report,upgrade` in the Docker/Vagrant provisioner options would skip it during idempotence without affecting the initial converge

**Recommendation:** add `upgrade` to `skip-tags` in Docker and Vagrant scenarios: `skip-tags: report,upgrade`. This way the initial converge runs the full upgrade, but the idempotence check only re-runs the package install (which should be truly idempotent).

**UPDATE to molecule.yml files:** all three scenarios should use `skip-tags: report,upgrade`.

### Package name portability

- The test package sets use only names verified to exist in both Arch and Ubuntu 24.04 repos.
- If a package is renamed or removed from a distro's repos, the converge will fail with a clear error from the package manager.
- `ripgrep` is available on both Arch and Ubuntu 24.04 but is excluded from the vagrant scenario to avoid risk with older Ubuntu versions. It IS included in the docker scenario (Arch-only).

### Vault removal

- The current `default/converge.yml` loads `vault.yml`. This role has zero vault variables. The vault dependency is removed in the shared converge to simplify testing and remove the requirement for `vault-pass.sh` to exist.
- If vault variables are ever needed (unlikely for a package-install role), they can be added back per-scenario.

### `packages_all` fact duplication in verify

- The verify playbook must rebuild the `packages_all` list because it runs as a separate play without access to facts set during converge.
- Using `vars_files: ../../defaults/main.yml` ensures all category lists have their default `[]` values, and the scenario's `group_vars` overrides take precedence.
- This duplication is an accepted trade-off. The alternative (caching the fact to a file during converge, reading it during verify) adds complexity with no real benefit.

### Container DNS

- The Docker scenario includes `dns_servers: [8.8.8.8, 8.8.4.4]` to ensure package downloads work inside the container. Without explicit DNS, some Docker hosts route container DNS through a local resolver that may not work.

### No `dependency` step in new scenarios

- The current `default/molecule.yml` has a `dependency` step that downloads Galaxy requirements. The packages role has `dependencies: []` in `meta/main.yml`, so no Galaxy downloads are needed.
- If collection dependencies are needed (e.g., `community.general` for the pacman module), they should be pre-installed in the CI environment or Docker image, not downloaded per-test-run.

---

## File Tree After Implementation

```
ansible/roles/packages/
  defaults/main.yml          (unchanged)
  meta/main.yml              (unchanged)
  tasks/
    main.yml                 (unchanged)
    install-archlinux.yml    (unchanged)
    install-debian.yml       (unchanged)
  molecule/
    shared/
      converge.yml           (NEW)
      verify.yml             (NEW)
    default/
      molecule.yml           (MODIFIED -- points to shared, vault removed)
    docker/
      molecule.yml           (NEW)
      prepare.yml            (NEW)
    vagrant/
      molecule.yml           (NEW)
      prepare.yml            (NEW)
```

Deleted files:
- `molecule/default/converge.yml` (replaced by `shared/converge.yml`)
- `molecule/default/verify.yml` (replaced by `shared/verify.yml`)
