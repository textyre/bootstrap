# Plan: hostctl -- Vagrant KVM Molecule Scenario

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### Role purpose

The `hostctl` role installs the [hostctl](https://github.com/guumaster/hostctl) binary and manages `/etc/hosts` profiles. hostctl is a Go CLI tool by guumaster for managing multiple host-file profiles with enable/disable semantics.

### Installation strategy (`tasks/install.yml`)

The role uses a three-tier fallback:

1. **Package manager** (`ansible.builtin.package`) for non-Arch systems -- tries `apt`/`dnf`/etc.
2. **AUR** (`kewlfft.aur.aur: hostctl-bin`) for Arch Linux via `yay`.
3. **GitHub releases fallback** (`tasks/download.yml`) -- downloads the Linux tarball, verifies SHA256 checksum, extracts binary to `/usr/local/bin/hostctl`.

On Ubuntu, tier 1 (`apt install hostctl`) will fail because there is no official apt repository. The role catches this (`failed_when: false`) and falls through to tier 3 (GitHub tarball). This means the role already works on Ubuntu without code changes -- the fallback path handles it.

### Profile management (`tasks/profiles.yml`)

Deploys `/etc/hostctl/<name>.hosts` files via Jinja2 template, then notifies a handler that runs `hostctl remove <profile>` + `hostctl add domains <profile> <host> --ip <ip>` to apply entries into `/etc/hosts`.

### Existing molecule scenarios

| Scenario | Driver | Platforms | Prepare | Notes |
|----------|--------|-----------|---------|-------|
| `default` | default (localhost) | Localhost | None | Runs on local machine, no container/VM |
| `docker` | docker | `Archlinux-systemd` (custom image) | Installs `kewlfft.aur` collection + creates `aur_builder` user | Arch-only |

Both scenarios reuse `molecule/shared/converge.yml` and `molecule/shared/verify.yml`.

### Shared converge.yml

Applies the `hostctl` role with:
- `hostctl_version: "1.1.4"` (pinned)
- `hostctl_verify_checksum: true`
- Two profiles: `dev` (app.local, api.local) and `registry` (registry.local)

### Shared verify.yml

Checks:
1. Binary exists at `/usr/local/bin/hostctl` with mode `0755`
2. `/etc/hostctl` directory exists
3. `hostctl --version` output contains `1.1.4`
4. Profile `.hosts` files exist and contain expected hostnames
5. `/etc/hosts` contains the profile entries (applied by handler)
6. Base `127.0.0.1` entry in `/etc/hosts` not overwritten

No platform-conditional logic exists -- all checks run on all hosts.

## 2. Cross-Platform Analysis

### Is hostctl available on Ubuntu?

**No official apt repository exists.** The upstream project provides:
- AUR package `hostctl-bin` (Arch)
- `.deb` packages in GitHub releases (e.g., `hostctl_1.1.4_linux_amd64.deb`)
- Pre-built tarballs in GitHub releases (all platforms)
- Homebrew tap, Nix, Scoop (not relevant here)
- Snap was deprecated at v1.0.11

### How the role handles Ubuntu

The role's `install.yml` tries `ansible.builtin.package: hostctl` first (tier 1). On Ubuntu this fails silently (`failed_when: false`). It then checks `command -v hostctl` and, finding nothing, falls through to `download.yml` (tier 3) which downloads the Linux tarball from GitHub releases.

**Result: hostctl installs on Ubuntu via GitHub tarball download. No code changes needed for the install path.**

### Handler compatibility

The handler uses `hostctl remove` and `hostctl add domains` shell commands. These are platform-independent -- they only manipulate `/etc/hosts`. Works identically on Arch and Ubuntu.

### Profile file deployment

Uses `ansible.builtin.template` and `ansible.builtin.file` -- fully cross-platform.

### Verdict

The role is **already cross-platform**. The vagrant scenario can run both Arch and Ubuntu without skipping either platform.

## 3. Vagrant Scenario

### New files

```
ansible/roles/hostctl/molecule/vagrant/
  molecule.yml
  prepare.yml
```

Reused without changes:
- `molecule/shared/converge.yml`
- `molecule/shared/verify.yml`

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

**Notes on `skip-tags`:**
- `report` -- skips debug-only report tasks (project convention).
- AUR tag is NOT skipped. On Arch, the AUR install path runs (tier 2). If `yay` is not present, it fails silently and falls through to the GitHub download (tier 3). This is acceptable because the purpose of the vagrant test is to validate the full install logic including fallback behavior on a real system.
- If installing `kewlfft.aur` collection and `yay` in prepare is undesirable, an alternative is to add `skip-tags: report,aur` to force the GitHub fallback on Arch. This is discussed in Section 6.

### prepare.yml

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

    - name: Install kewlfft.aur collection on controller (for Arch AUR path)
      ansible.builtin.command: ansible-galaxy collection install kewlfft.aur
      delegate_to: localhost
      run_once: true
      changed_when: true

    - name: Create aur_builder user on Arch (for AUR privilege escalation)
      ansible.builtin.user:
        name: aur_builder
        system: true
        create_home: false
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Allow aur_builder passwordless sudo on Arch
      ansible.builtin.lineinfile:
        path: /etc/sudoers.d/aur_builder
        line: "aur_builder ALL=(ALL) NOPASSWD: /usr/bin/pacman"
        create: true
        mode: '0440'
        validate: /usr/sbin/visudo -cf %s
      when: ansible_facts['os_family'] == 'Archlinux'
```

**Key differences from docker prepare:**
- Python bootstrap via `raw` (Vagrant Arch box may not have Python pre-installed).
- Pacman keyring refresh (generic/arch box ships with stale keys -- proven issue in `package_manager` vagrant testing).
- Full system upgrade (prevents SSL/library version mismatches between base packages and newly installed ones).
- `apt update` for Ubuntu.
- `kewlfft.aur` collection install delegated to localhost (controller) -- needed for the AUR task in `install.yml`.
- `aur_builder` user creation with sudoers entry (same as docker prepare but with proper sudo config for real VM).

**Note:** If `skip-tags: report,aur` is used in molecule.yml, the AUR-related prepare tasks (`kewlfft.aur` install, `aur_builder` creation, sudoers entry) can be removed. The `yay` binary won't be present, so the role will skip the AUR path and go straight to GitHub fallback on Arch. This simplifies prepare.yml but tests a different code path than production.

## 4. Shared verify.yml Cross-Platform Fixes

The current `verify.yml` is **already cross-platform compatible** -- no platform-conditional logic is needed because:

1. **Binary check** (`/usr/local/bin/hostctl`): Both Arch (GitHub fallback) and Ubuntu (GitHub fallback) install to this path. Even if Arch uses AUR, the `hostctl-bin` AUR package installs to `/usr/bin/hostctl`, which would fail the verify check at `/usr/local/bin/hostctl`. This is actually a potential issue -- see Section 6 Risk R-02.

2. **Version check**: `hostctl --version` works identically on both platforms.

3. **Profile files**: `/etc/hostctl/*.hosts` files are deployed by `ansible.builtin.template` -- platform-independent.

4. **`/etc/hosts` integration**: The handler applies profiles via `hostctl add domains` which modifies `/etc/hosts` on any Linux system.

5. **Base `127.0.0.1` check**: Both Arch and Ubuntu have `127.0.0.1` in `/etc/hosts` by default.

### Potential change: binary path flexibility

If AUR installs to `/usr/bin/hostctl` instead of `/usr/local/bin/hostctl`, the verify check for binary path will fail on Arch when AUR succeeds. Two options:

**Option A (recommended):** Keep `skip-tags: report` (no AUR skip), accept that AUR may or may not succeed on Arch vagrant. If AUR fails, fallback installs to `/usr/local/bin/hostctl` and verify passes. If AUR succeeds, binary is at `/usr/bin/hostctl` and verify fails.

To handle this, change verify.yml to check `command -v hostctl` instead of a hardcoded path:

```yaml
  vars:
    verify_version_string: "1.1.4"
    # ... profiles stay the same

  tasks:
    - name: Locate hostctl binary
      ansible.builtin.command: command -v hostctl
      register: hostctl_verify_which
      changed_when: false

    - name: Set binary path fact
      ansible.builtin.set_fact:
        verify_binary: "{{ hostctl_verify_which.stdout | trim }}"

    - name: Verify hostctl binary exists at install path
      ansible.builtin.stat:
        path: "{{ verify_binary }}"
      register: hostctl_verify_bin
    # ... rest unchanged, using dynamic verify_binary
```

**Option B (simpler):** Use `skip-tags: report,aur` in vagrant molecule.yml to force GitHub fallback on Arch. Binary always lands at `/usr/local/bin/hostctl`. Verify passes unchanged.

**Recommendation:** Option B for the vagrant scenario. It keeps verify.yml unchanged and tests the GitHub download path (which is the path Ubuntu always uses). The docker scenario already tests the AUR path on Arch.

## 5. Implementation Order

1. **Create `molecule/vagrant/molecule.yml`**
   - Copy the YAML from Section 3.
   - Use `skip-tags: report` (or `report,aur` per Option B decision).

2. **Create `molecule/vagrant/prepare.yml`**
   - Copy the YAML from Section 3.
   - If Option B: remove `kewlfft.aur`, `aur_builder`, and sudoers tasks.

3. **Verify shared converge.yml compatibility**
   - The converge pins `hostctl_version: "1.1.4"`. This version has both `.tar.gz` and `.deb` assets on GitHub releases.
   - The role's `download.yml` downloads the tarball (not `.deb`), so it works on both platforms.
   - No changes needed.

4. **Verify shared verify.yml compatibility**
   - If Option B (skip AUR): no changes needed -- binary always at `/usr/local/bin/hostctl`.
   - If Option A: apply the `command -v` dynamic path change.

5. **Local test run**
   ```bash
   cd ansible/roles/hostctl
   molecule test -s vagrant
   ```

6. **CI workflow** (if applicable)
   - Add `hostctl` to the role list in the vagrant molecule CI workflow, or create a dedicated workflow entry.

## 6. Risks and Notes

### R-01: GitHub API rate limiting

The `download.yml` task queries the GitHub API to resolve the release. GitHub's unauthenticated rate limit is 60 requests/hour per IP. In CI, multiple roles testing simultaneously could exhaust this.

**Mitigation:** The converge pins `hostctl_version: "1.1.4"`, so the API call hits `/releases/tags/v1.1.4` (a specific endpoint, not search). Still counts against rate limit. If this becomes an issue, set `GITHUB_TOKEN` in the molecule provisioner env.

### R-02: AUR install path vs verify binary path

The AUR package `hostctl-bin` installs the binary to `/usr/bin/hostctl`. The verify.yml hardcodes `/usr/local/bin/hostctl`. If the AUR install succeeds on Arch, the `command -v hostctl` check in `install.yml` (line 62) finds it at `/usr/bin/hostctl` and skips the GitHub download. But verify.yml then fails because it checks `/usr/local/bin/hostctl`.

**Impact:** Only affects Arch when AUR succeeds AND `yay` is available. In the vagrant scenario, `yay` is not pre-installed in `generic/arch` box and prepare.yml does not install it.

**Mitigation options:**
- Skip AUR tag in vagrant (`skip-tags: report,aur`) -- recommended, simplest.
- Make verify.yml use `command -v hostctl` for dynamic path detection.
- Accept that AUR path is tested by docker scenario only.

### R-03: `generic/arch` box freshness

The `generic/arch` Vagrant box is community-maintained and may lag behind Arch rolling releases. Stale packages + stale keyring are a known issue (documented in `package_manager` vagrant postmortem).

**Mitigation:** The prepare.yml includes keyring refresh + full system upgrade, matching the proven pattern from `package_manager/molecule/vagrant/prepare.yml`.

### R-04: GitHub download requires internet access

The `download.yml` task downloads from `github.com`. Vagrant VMs need outbound HTTPS access.

**Mitigation:** Default Vagrant networking (NAT) provides outbound internet. No special config needed.

### R-05: Idempotence check and handler behavior

The handler runs `hostctl remove <profile> || true` + `hostctl add domains ...` on every notify. On second converge (idempotence check), if the template file has not changed, the handler does not fire. However, if the handler fires for any reason, it always reports `changed: true` (`changed_when: true` in the handler).

**Impact:** Idempotence check should pass because the template task will report `ok` (not `changed`) on second run, so the handler won't be notified.

### R-06: No `.deb` install path tested

The role's `download.yml` always uses the tarball path (`.tar.gz`), even on Ubuntu where a `.deb` is available. The `ansible.builtin.package: hostctl` task (tier 1) fails silently because there's no apt repo. The `.deb` from GitHub releases is never used.

**Impact:** Not a testing gap -- the role intentionally uses tarball for all GitHub fallback installs. The `.deb` path is simply not part of the role's design. If `.deb` install support is desired in the future, `download.yml` would need a conditional branch for Debian-family systems using `ansible.builtin.apt: deb=<url>`.

### Recommendation summary

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| AUR in vagrant | Skip (`skip-tags: report,aur`) | Avoids yay dependency, keeps prepare simple, tests GitHub fallback (same path Ubuntu uses) |
| verify.yml changes | None needed | With AUR skipped, binary always at `/usr/local/bin/hostctl` |
| prepare.yml base | Copy from `package_manager` vagrant | Proven pattern for keyring + upgrade + apt cache |
| AUR-specific prepare tasks | Omit if skipping AUR | No `aur_builder` user, no `kewlfft.aur` collection needed |
