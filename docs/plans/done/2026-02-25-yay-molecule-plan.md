# Plan: yay role -- Molecule testing (shared + Docker + Vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/yay/`

---

## 1. Current State

### What the role does

The `yay` role installs the [yay](https://github.com/Jguer/yay) AUR helper on Arch Linux, then
optionally installs AUR packages through it. The role is Arch-only (`meta/main.yml` declares
only ArchLinux).

**Three-phase execution** (`tasks/main.yml`):

1. **setup-aur-builder.yml** -- creates a dedicated `aur_builder` system user with
   `shell: /usr/bin/nologin`, and grants it `NOPASSWD: /usr/bin/pacman` via
   `/etc/sudoers.d/yay-aur-builder`. This user exists solely for `makepkg` (which refuses
   to run as root).

2. **setup-yay-binary.yml** -- checks if yay is already installed (and whether the binary has
   broken shared libs after a Go upgrade via `ldd`). If missing or broken:
   - Installs build dependencies (`base-devel`, `git`, `go`)
   - Creates a temp directory as `aur_builder`
   - Clones `https://aur.archlinux.org/yay.git`
   - Runs `makepkg --noconfirm` as `aur_builder`
   - Finds the built `.pkg.tar.*` and installs it via `community.general.pacman`
   - Cleans up the temp directory in an `always:` block

3. **manage-aur-packages.yml** -- removes conflict packages, validates AUR-vs-official conflicts
   via `validate-aur-conflicts.sh`, and installs AUR packages using `kewlfft.aur.aur` module
   with `use: yay` as `aur_builder`. This phase is conditional on `yay_packages_aur` being
   non-empty.

**Key variables** (`defaults/main.yml`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `yay_source_url` | `https://aur.archlinux.org/yay.git` | AUR git repo |
| `yay_builder_user` | `aur_builder` | Dedicated non-root build user |
| `yay_builder_sudoers_file` | `yay-aur-builder` | Sudoers drop-in filename |
| `yay_build_deps` | `[base-devel, git, go]` | Build-time dependencies |
| `yay_packages_aur` | `[]` | AUR packages to install |
| `yay_packages_aur_remove_conflicts` | `[]` | Official packages to remove before AUR install |
| `yay_packages_official` | `[]` | Official packages list (for conflict validation) |

**External dependency:** `kewlfft.aur` Ansible collection (provides `kewlfft.aur.aur` module).

### What tests exist now

Single `molecule/default/` scenario using the delegated (localhost) driver:

- **molecule.yml:** `driver: default`, `managed: false`, localhost with `ansible_connection: local`.
  Requires vault password (`vault-pass.sh`). Sets inline group_vars for yay configuration
  including a test AUR package (`rofi-greenclip`).
- **converge.yml:** Asserts `os_family == Archlinux`, loads vault vars, applies `yay` role.
- **verify.yml:** 10 assertions:
  1. `aur_builder` user exists via `getent`
  2. `aur_builder` has `/usr/bin/nologin` shell
  3. Sudoers file exists at `/etc/sudoers.d/yay-aur-builder`
  4. Sudoers file mode is `0440`
  5. Sudoers syntax valid (`visudo -cf`)
  6. Build dependencies installed (idempotency check via `check_mode`)
  7. `yay` binary exists (`which yay`)
  8. `yay --version` succeeds
  9. No broken shared libs (`ldd /usr/bin/yay`)
  10. No leftover `/tmp/yay_build_*` directories
  11. AUR packages installed (`pacman -Q`)

**Gaps:**
- No Docker or Vagrant scenarios
- Converge/verify not in `shared/` (not reusable across scenarios)
- Vault dependency in converge (the role itself has no vault variables)
- Test AUR package `rofi-greenclip` defined inline in molecule.yml, not reusable
- No idempotence step in test sequence

---

## 2. AUR Build Challenge

### Why yay is hard to test in containers/CI

The yay role is fundamentally different from most Ansible roles because it performs a
**multi-step build from source** that requires:

1. **A non-root user.** `makepkg` refuses to run as root with the error
   `ERROR: Running makepkg as root is not allowed as it can cause permanent, catastrophic
   damage to your system.` The role handles this by creating the `aur_builder` system user.

2. **Internet access.** The build process clones from `aur.archlinux.org` and `makepkg`
   downloads Go module dependencies. Without network access, the build fails.

3. **A working Go toolchain.** `yay` is written in Go. Building requires `go` (from `base-devel`
   group), which needs to download modules from `proxy.golang.org`.

4. **pacman package manager.** The built package is installed via `pacman -U`, requiring an
   Arch Linux environment with a functional package database.

5. **sudo access for the build user.** `makepkg` calls `sudo pacman` to install dependencies.
   The role grants this via the sudoers drop-in.

### Docker-specific challenges

| Challenge | Impact | Mitigation |
|-----------|--------|------------|
| Root-only container | `makepkg` refuses to run | Role creates `aur_builder` user -- works in container |
| No sudo installed | `become_user` fails | `arch-systemd` image includes `sudo` |
| No git/go/base-devel | Build fails | Role installs them via `pacman` |
| Network isolation | Cannot clone AUR or download Go modules | Use `dns_servers: [8.8.8.8, 8.8.4.4]` in molecule.yml |
| Build time | Go compilation takes 2-5 minutes | Acceptable for CI; cache not available |
| Container disk space | Go downloads + compilation artifacts | `/tmp` is tmpfs but typically sufficient |

### Existing solution

The current `molecule/default/` scenario avoids these problems by running directly on the host
(localhost driver on an Arch Linux VM). The role's own code already handles the non-root
requirement via `aur_builder`. The build works because the VM has full internet access and a
real Arch environment.

### Proposed Docker approach

The `arch-systemd` Docker image (`ghcr.io/textyre/bootstrap/arch-systemd:latest`) already
provides `python`, `sudo`, and systemd. The privileged container with DNS servers provides
network access. The role's existing task structure (create user, grant sudo, clone, build,
install) should work inside a privileged Docker container **without modification**, because:

- The container runs as root (Ansible `become: true` works)
- `become_user: aur_builder` works with sudo (installed in the image)
- DNS servers enable AUR git clone and Go module download
- `pacman` is functional inside the Arch container

The main risk is **build time** (Go compilation) and **network reliability** in CI. The AUR
package installation step (`kewlfft.aur.aur`) should be **skipped** in the Docker scenario
to avoid testing a third-party collection and to isolate the role's core responsibility
(installing yay itself). This is achieved by not setting `yay_packages_aur` (it defaults
to `[]`, which skips the `manage-aur-packages.yml` include).

---

## 3. Docker Scenario

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

**Notable decisions:**

- **No idempotence step.** The yay build is conditional (`yay_exists.rc != 0`), so the second
  converge run would skip the entire build block. However, the `makepkg` command uses
  `changed_when: true` (always reports changed). Since the block is skipped on second run,
  idempotence should pass -- but the build itself takes 2-5 minutes, doubling CI time for
  no additional coverage. Omitted to save CI time.
- **No `yay_packages_aur` set.** The Docker scenario tests yay installation only, not AUR
  package management. This avoids testing `kewlfft.aur.aur` in Docker (which would require
  the collection installed and additional network access) and keeps the test focused.
- **No vault.** The role has no vault variables. The current default scenario uses vault only
  because the converge.yml loads it -- the shared converge will not.

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

Same pattern as the `ntp` Docker prepare.

### AUR build in Docker -- expected flow

1. **prepare.yml** -- updates pacman cache
2. **converge.yml** -- applies yay role:
   - Creates `aur_builder` user (succeeds -- `useradd` works in container)
   - Creates sudoers drop-in (succeeds -- `/etc/sudoers.d/` exists)
   - Checks `yay --version` (fails -- not installed yet)
   - Installs `base-devel`, `git`, `go` via pacman (succeeds -- cache is fresh)
   - Creates temp dir as `aur_builder` (succeeds -- sudo + user exist)
   - Clones yay from AUR (succeeds -- DNS servers provide internet)
   - Runs `makepkg --noconfirm` as `aur_builder` (succeeds -- Go downloads modules via internet)
   - Installs built package via pacman (succeeds)
   - Cleans up temp dir (succeeds)
   - Verifies `yay --version` (succeeds)
3. **verify.yml** -- runs assertions (all should pass)

### Risk: Go module download failure

If `proxy.golang.org` is unreachable (corporate firewall, DNS failure), `makepkg` will fail
during the Go build step. This is an inherent limitation of building from source.

**Mitigation:** The DNS servers `8.8.8.8` / `8.8.4.4` are set explicitly. In GitHub Actions
this is sufficient. For local testing behind a proxy, users can set `MOLECULE_ARCH_IMAGE` to
a custom image with Go modules pre-cached, or run the localhost scenario instead.

---

## 4. Vagrant Scenario

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

**Arch-only:** yay is fundamentally an Arch Linux / AUR tool. There is no Ubuntu or Debian
platform because:
- The role asserts `os_family == Archlinux` and fails on other distributions
- AUR does not exist outside the Arch ecosystem
- `makepkg` and `pacman` are Arch-specific tools

**No idempotence step** for the same reasons as Docker (build time).

**Memory: 2048 MB** -- Go compilation is memory-intensive. 1024 MB may cause OOM during
`makepkg`.

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
      changed_when: true

    - name: Full system upgrade on Arch (ensures openssl/go compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
```

This follows the established `package_manager` vagrant prepare pattern. The keyring refresh
is critical because `generic/arch` boxes ship with stale GPG keys that cause package
signature verification failures. The full system upgrade ensures that `go` (installed during
converge) is compatible with the system's OpenSSL and glibc.

### Vagrant AUR build advantages over Docker

| Aspect | Docker | Vagrant |
|--------|--------|---------|
| Internet access | Via DNS servers, may be filtered | Full NAT, reliable |
| Non-root user | Works via sudo | Works via sudo |
| Filesystem | Overlay, tmpfs | Real disk |
| Build speed | Fast I/O but tmpfs limits | Slower I/O but no limits |
| Go modules | May fail behind proxy | Reliable |
| Cleanup | Container destroyed | VM destroyed |
| CI suitability | GitHub Actions (fast) | Local only (slow startup) |

---

## 5. Shared Migration

Move `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/`
so Docker, Vagrant, and default scenarios all reuse the same playbooks.

### molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: yay
```

**Changes from current `default/converge.yml`:**
- **Removed** `vars_files` vault reference (role has no vault variables; vault was inherited
  from other role patterns but serves no purpose here)
- **Removed** `pre_tasks` Archlinux assertion (the role's `tasks/main.yml` already asserts
  `os_family == Archlinux` -- duplicating it in converge is redundant)

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
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
    group_vars:
      all:
        yay_source_url: "https://aur.archlinux.org/yay.git"
        yay_builder_user: "aur_builder"
        yay_builder_sudoers_file: "yay-aur-builder"
        yay_build_deps:
          - base-devel
          - git
          - go
        yay_packages_aur:
          - rofi-greenclip
        yay_packages_aur_remove_conflicts: []
        yay_packages_official:
          - git
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
- **Removed** `vault_password_file` (not needed)
- **Changed** playbook paths to `../shared/`
- **Changed** `ANSIBLE_ROLES_PATH` from `roles` to `${MOLECULE_PROJECT_DIRECTORY}/../`
  (consistent with other roles -- resolves to `ansible/roles/`)
- **Kept** inline group_vars with `yay_packages_aur: [rofi-greenclip]` for the localhost
  scenario (this scenario runs on a real Arch VM where AUR package install is testable)
- **Removed** `idempotence` from test sequence (was already absent; `makepkg` cannot be
  idempotent without significant complexity)

### Old files to delete

```
ansible/roles/yay/molecule/default/converge.yml  (moved to shared/)
ansible/roles/yay/molecule/default/verify.yml     (moved to shared/)
```

---

## 6. Verify.yml Design

### molecule/shared/verify.yml

```yaml
---
- name: Verify yay role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- aur_builder user ----

    - name: Check that aur_builder user exists
      ansible.builtin.getent:
        database: passwd
        key: "{{ yay_builder_user }}"
      register: yay_verify_aur_builder

    - name: Assert aur_builder has nologin shell
      ansible.builtin.assert:
        that:
          - yay_verify_aur_builder.ansible_facts.getent_passwd[yay_builder_user][5] == '/usr/bin/nologin'
        fail_msg: >-
          aur_builder shell is '{{ yay_verify_aur_builder.ansible_facts.getent_passwd[yay_builder_user][5] }}',
          expected '/usr/bin/nologin'

    - name: Assert aur_builder is a system user (UID < 1000)
      ansible.builtin.assert:
        that:
          - yay_verify_aur_builder.ansible_facts.getent_passwd[yay_builder_user][1] | int < 1000
        fail_msg: >-
          aur_builder UID is {{ yay_verify_aur_builder.ansible_facts.getent_passwd[yay_builder_user][1] }},
          expected < 1000 (system user)

    # ---- sudoers ----

    - name: Stat sudoers drop-in file
      ansible.builtin.stat:
        path: "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
      register: yay_verify_sudoers

    - name: Assert sudoers file exists
      ansible.builtin.assert:
        that: yay_verify_sudoers.stat.exists
        fail_msg: "/etc/sudoers.d/{{ yay_builder_sudoers_file }} does not exist"

    - name: Assert sudoers file has correct permissions
      ansible.builtin.assert:
        that:
          - yay_verify_sudoers.stat.mode == '0440'
          - yay_verify_sudoers.stat.pw_name == 'root'
          - yay_verify_sudoers.stat.gr_name == 'root'
        fail_msg: >-
          /etc/sudoers.d/{{ yay_builder_sudoers_file }} permissions incorrect:
          mode={{ yay_verify_sudoers.stat.mode }} owner={{ yay_verify_sudoers.stat.pw_name }}
          group={{ yay_verify_sudoers.stat.gr_name }} (expected 0440 root:root)

    - name: Validate sudoers syntax
      ansible.builtin.command: /usr/sbin/visudo -cf "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
      changed_when: false

    - name: Read sudoers file content
      ansible.builtin.slurp:
        src: "/etc/sudoers.d/{{ yay_builder_sudoers_file }}"
      register: yay_verify_sudoers_raw

    - name: Assert sudoers grants NOPASSWD pacman only
      ansible.builtin.assert:
        that:
          - "'NOPASSWD: /usr/bin/pacman' in (yay_verify_sudoers_raw.content | b64decode)"
          - "yay_builder_user in (yay_verify_sudoers_raw.content | b64decode)"
        fail_msg: >-
          Sudoers content does not match expected pattern.
          Expected '{{ yay_builder_user }} ALL=(root) NOPASSWD: /usr/bin/pacman'

    # ---- build dependencies ----

    - name: Check that build dependencies are installed
      ansible.builtin.package:
        name: "{{ item }}"
        state: present
      check_mode: true
      register: yay_verify_dep_check
      failed_when: yay_verify_dep_check is changed
      loop: "{{ yay_build_deps }}"

    # ---- yay binary ----

    - name: Check that yay binary exists
      ansible.builtin.command: which yay
      changed_when: false
      register: yay_verify_path

    - name: Assert yay is at /usr/bin/yay
      ansible.builtin.assert:
        that: "'/usr/bin/yay' in yay_verify_path.stdout"
        fail_msg: "yay binary not at expected path /usr/bin/yay (got: {{ yay_verify_path.stdout }})"

    - name: Check that yay is executable and reports version
      ansible.builtin.command: yay --version
      changed_when: false
      register: yay_verify_version

    - name: Assert yay version output is valid
      ansible.builtin.assert:
        that: "'yay' in yay_verify_version.stdout"
        fail_msg: "yay --version did not produce expected output: {{ yay_verify_version.stdout }}"

    - name: Check that yay has no broken shared libs
      ansible.builtin.command: ldd /usr/bin/yay
      changed_when: false
      register: yay_verify_ldd
      failed_when: "'not found' in yay_verify_ldd.stdout"

    # ---- build cleanup ----

    - name: Check that temp build directories were cleaned up
      ansible.builtin.find:
        paths: /tmp
        patterns: "yay_build_*"
        file_type: directory
      register: yay_verify_build_dirs

    - name: Assert no leftover build directories
      ansible.builtin.assert:
        that: yay_verify_build_dirs.matched == 0
        fail_msg: >-
          Found {{ yay_verify_build_dirs.matched }} leftover build directories in /tmp:
          {{ yay_verify_build_dirs.files | map(attribute='path') | list }}

    # ---- AUR packages (conditional -- only when yay_packages_aur is set) ----

    - name: Check that AUR packages are installed
      ansible.builtin.command: "pacman -Q {{ item }}"
      loop: "{{ yay_packages_aur }}"
      changed_when: false
      when: yay_packages_aur | default([]) | length > 0

    # ---- aur_builder can execute yay (functional test) ----

    - name: Verify aur_builder can run yay --version
      ansible.builtin.command: yay --version
      become: true
      become_user: "{{ yay_builder_user }}"
      changed_when: false
      register: yay_verify_builder_exec

    - name: Assert aur_builder yay execution succeeded
      ansible.builtin.assert:
        that: yay_verify_builder_exec.rc == 0
        fail_msg: >-
          aur_builder cannot execute yay (rc={{ yay_verify_builder_exec.rc }}).
          This may indicate permission or PATH issues.

    # ---- summary ----

    - name: Show verify results
      ansible.builtin.debug:
        msg:
          - "All yay role checks passed!"
          - "aur_builder: user exists, UID < 1000, shell=/usr/bin/nologin"
          - "sudoers: /etc/sudoers.d/{{ yay_builder_sudoers_file }} (0440, root:root, valid syntax)"
          - "yay binary: {{ yay_verify_path.stdout }}"
          - "yay version: {{ yay_verify_version.stdout }}"
          - "yay ldd: OK (no broken shared libs)"
          - "Build deps: {{ yay_build_deps | join(', ') }} installed"
          - "Temp build dirs: cleaned up (0 found)"
          - "AUR packages: {{ yay_packages_aur | default([]) | join(', ') | default('(none -- skipped)', true) }}"
          - "aur_builder can execute yay: yes"
```

### Assertion summary table

| # | Assertion | What it validates |
|---|-----------|-------------------|
| 1 | `aur_builder` user exists | `getent passwd` lookup |
| 2 | Shell is `/usr/bin/nologin` | Security: no interactive login |
| 3 | UID < 1000 | System user, not regular user |
| 4 | Sudoers file exists | Drop-in created |
| 5 | Sudoers permissions `0440 root:root` | Security: correct ownership and mode |
| 6 | Sudoers syntax valid | `visudo -cf` passes |
| 7 | Sudoers content has `NOPASSWD: /usr/bin/pacman` | Correct privilege scope |
| 8 | Build deps installed | `base-devel`, `git`, `go` present |
| 9 | `yay` binary at `/usr/bin/yay` | Correct install location |
| 10 | `yay --version` succeeds | Binary is functional |
| 11 | No broken shared libs (`ldd`) | Binary not corrupted by Go upgrade |
| 12 | No `/tmp/yay_build_*` dirs | `always:` cleanup worked |
| 13 | AUR packages installed | `pacman -Q` (conditional) |
| 14 | `aur_builder` can execute yay | Functional test of user + binary |

### Differences from current verify.yml

| Change | Reason |
|--------|--------|
| Added UID < 1000 assertion | Verifies `system: true` in user creation |
| Added sudoers permissions (owner/group) | Currently only checks mode, not ownership |
| Added sudoers content assertion | Verifies the actual NOPASSWD line, not just file existence |
| Added `/usr/bin/yay` path assertion | Verifies expected install location |
| Added `yay` in version output assertion | Validates output format |
| Added `aur_builder` functional test | Verifies the user can actually run yay |
| AUR packages check is conditional | Allows Docker scenario to skip (no packages set) |
| Uses `yay_verify_*` register prefix | Follows project convention (avoids collisions) |
| Loads `../../defaults/main.yml` | Variables available without vault or inline group_vars |
| Removed vault `vars_files` | Role has no vault variables |

---

## 7. Implementation Order

### Step 1: Create `molecule/shared/` directory

```bash
mkdir -p ansible/roles/yay/molecule/shared/
```

### Step 2: Create `molecule/shared/converge.yml`

Simplified playbook without vault or Arch assertion (Section 5).

### Step 3: Create `molecule/shared/verify.yml`

Comprehensive assertions from Section 6.

### Step 4: Update `molecule/default/molecule.yml`

- Remove `vault_password_file`
- Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
- Fix `ANSIBLE_ROLES_PATH` to `${MOLECULE_PROJECT_DIRECTORY}/../`
- Keep inline group_vars (localhost scenario needs them for AUR package testing)

### Step 5: Delete old `molecule/default/converge.yml` and `molecule/default/verify.yml`

```bash
rm ansible/roles/yay/molecule/default/converge.yml
rm ansible/roles/yay/molecule/default/verify.yml
```

### Step 6: Create `molecule/docker/` directory and files

```bash
mkdir -p ansible/roles/yay/molecule/docker/
```

Create `molecule.yml` and `prepare.yml` per Section 3.

### Step 7: Create `molecule/vagrant/` directory and files

```bash
mkdir -p ansible/roles/yay/molecule/vagrant/
```

Create `molecule.yml` and `prepare.yml` per Section 4.

### Step 8: Test Docker scenario locally

```bash
cd ansible/roles/yay && molecule test -s docker
```

Expected: yay builds from source in ~3-5 minutes, all verify assertions pass.

### Step 9: Test Vagrant scenario locally (requires libvirt)

```bash
cd ansible/roles/yay && molecule test -s vagrant
```

Expected: VM boots, keyring refreshes, yay builds, all assertions pass.

### Step 10: Test default scenario (localhost, existing Arch VM)

```bash
cd ansible/roles/yay && molecule test -s default
```

Expected: uses shared converge/verify, all assertions pass (including AUR packages).

---

## 8. Risks / Notes

### AUR build in CI (network dependency)

**Risk:** The yay build requires cloning from `aur.archlinux.org` and downloading Go modules
from `proxy.golang.org`. If either is unreachable, the Docker scenario fails.

**Mitigation:** GitHub Actions runners have reliable internet access. The `dns_servers`
configuration ensures DNS resolution works inside the container. For transient failures,
CI retry is the pragmatic approach.

**Alternative considered and rejected:** Pre-building yay into the `arch-systemd` Docker image.
This would make the image specific to the yay role and violate the image contract (generic
Arch systemd container). It would also skip testing the actual build process, which is the
role's core function.

### Build time in CI

**Risk:** Go compilation takes 2-5 minutes. Adding idempotence testing would double this.

**Mitigation:** Idempotence is omitted from Docker and Vagrant test sequences. The role is
designed to be idempotent via its `yay --version` check-before-build pattern, but verifying
this in CI is not worth the time cost.

### Why Ubuntu / Debian are excluded

yay is the **Arch User Repository** helper. It has no meaning outside Arch Linux:
- The AUR only contains Arch packages (PKGBUILDs that produce `.pkg.tar.*`)
- `makepkg` is an Arch-specific tool (part of `pacman`)
- `pacman` is the Arch package manager
- The role's first task asserts `os_family == Archlinux` and fails otherwise

Adding an Ubuntu platform to the Vagrant scenario would result in an immediate assertion
failure. This is by design.

### kewlfft.aur collection dependency

The `manage-aur-packages.yml` task file uses `kewlfft.aur.aur`. This collection must be
installed on the Ansible controller. In the Docker scenario, AUR package management is
skipped (no `yay_packages_aur` set), so the collection is not required for Docker tests.
In the default (localhost) scenario, the collection must be available.

### Vagrant `generic/arch` stale keyring

**Risk:** The `generic/arch` Vagrant box ships with outdated GPG keys. Installing packages
fails with `error: key "..." could not be looked up remotely` or signature verification
errors.

**Mitigation:** The prepare.yml temporarily disables signature verification, updates
`archlinux-keyring`, then re-enables signatures and runs `pacman-key --populate`. This is
the established pattern from the `package_manager` vagrant scenario and has been validated
in production.

### Go version compatibility

**Risk:** If the Arch container or VM has a very old Go version, it may not support the
Go module features required by yay's `go.mod`.

**Mitigation:** The prepare.yml runs `pacman -Syu` (full system upgrade), which brings Go
to the latest available version. The Docker scenario's prepare does `update_cache` only,
but the role's `Install build dependencies` task installs the latest `go` package from
the (updated) repos.

### `ldd` check for Go static binaries

**Risk:** Newer versions of yay may be compiled as fully static Go binaries. In that case,
`ldd /usr/bin/yay` may report `not a dynamic executable` (exit code 1), which is not the
same as a broken shared library. The current verify checks `failed_when: "'not found' in stdout"`,
which would not trigger on a static binary -- but `ldd` might print to stderr and have a
non-zero exit code.

**Mitigation:** The role's `setup-yay-binary.yml` uses `failed_when: false` on the ldd check
and only looks for `"not found"` in stdout. The verify.yml does the same. If yay becomes
a static binary, the ldd check would still pass (no "not found" in output). A future
improvement could add a `file /usr/bin/yay` check to determine if it is static or dynamic.

---

## File tree after implementation

```
ansible/roles/yay/
  defaults/main.yml                    (unchanged)
  files/validate-aur-conflicts.sh      (unchanged)
  meta/main.yml                        (unchanged)
  tasks/
    main.yml                           (unchanged)
    setup-aur-builder.yml              (unchanged)
    setup-yay-binary.yml               (unchanged)
    manage-aur-packages.yml            (unchanged)
  molecule/
    shared/
      converge.yml                     (NEW -- simplified, no vault)
      verify.yml                       (NEW -- 14 assertions)
    default/
      molecule.yml                     (UPDATED -- point to shared/, remove vault)
    docker/
      molecule.yml                     (NEW -- arch-systemd container)
      prepare.yml                      (NEW -- pacman update_cache)
    vagrant/
      molecule.yml                     (NEW -- arch-vm only)
      prepare.yml                      (NEW -- Python bootstrap, keyring refresh, syu)
```
