# Plan: sysctl -- Molecule testing + GAP-03/MED-02 fixes

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### Role overview

The `sysctl` role deploys a Jinja2-templated drop-in file to `/etc/sysctl.d/99-ansible.conf` and applies it via `sysctl -e --system` (handler). It supports Arch Linux and Debian/Ubuntu and provides four task files orchestrated by `tasks/main.yml`:

| File | Purpose |
|------|---------|
| `tasks/packages.yml` | Install `procps-ng` (Arch) or `procps` (Debian) |
| `tasks/deploy.yml` | Create `/etc/sysctl.d/` dir, template the drop-in config |
| `tasks/verify.yml` | Read live sysctl values, report OK/MISMATCH/NOT SUPPORTED |
| `tasks/report.yml` | Debug summary of key values |

**Tags:** `sysctl`, `configure`, `packages`, `verify`.

**Handler:** `listen: "reload sysctl"` runs `sysctl -e --system`. The `-e` flag silently ignores unsupported parameters (e.g. `kernel.unprivileged_userns_clone` on non-hardened kernels).

**Feature toggles (defaults/main.yml):**
- `sysctl_security_enabled` (master switch)
- `sysctl_security_kernel_hardening`
- `sysctl_security_network_hardening`
- `sysctl_security_filesystem_hardening`
- `sysctl_security_ipv6_disable`

### Existing tests

**molecule/default/** -- localhost-only (runs on the developer's actual machine):
- `converge.yml`: asserts `os_family == Archlinux`, applies the role
- `verify.yml`: checks drop-in file exists, greps for `vm.swappiness`, reads live values for 3 performance params and 9 security params via `sysctl -n`, asserts match
- `molecule.yml`: uses vault password file, `default` driver (unmanaged localhost)

**No docker scenario exists. No vagrant scenario exists. No shared/ directory exists.**

### Bug: `_sysctl_supported_os` undefined

`tasks/main.yml` references `_sysctl_supported_os` (private, underscore prefix) but `defaults/main.yml` defines `sysctl_supported_os` (public, no underscore). There is no `vars/main.yml` to bridge them. This means the `when:` guards evaluate against an undefined variable, which Ansible treats as falsy -- **the role silently skips all tasks unless the caller defines `_sysctl_supported_os` explicitly or the variable resolution happens to work via some other mechanism.**

**Fix:** Either rename the variable in `defaults/main.yml` to `_sysctl_supported_os` (convention: internal vars use underscore) or rename in `tasks/main.yml` to match the public name. The project convention (see `package_manager`) is to use `_rolename_` prefix for internal vars. Recommended: add `vars/main.yml` with `_sysctl_supported_os: "{{ sysctl_supported_os }}"` or directly define the private list there.

---

## 2. GAP-03 Fix Plan: Missing Security Parameters

### Analysis

The code review (2026-02-17) identified 11 missing parameters. After reading the actual `defaults/main.yml` and `sysctl.conf.j2`, the role has **already been updated** to include all originally-missing parameters. Current state:

| Parameter | In defaults? | In template? | In verify.yml (task)? | In molecule verify? |
|-----------|:---:|:---:|:---:|:---:|
| `kernel.perf_event_paranoid: 3` | YES (line 61) | YES (line 54) | YES (line 16) | NO |
| `kernel.unprivileged_bpf_disabled: 1` | YES (line 64) | YES (line 58) | YES (line 17) | NO |
| `net.ipv4.tcp_timestamps: 0` | YES (line 113) | YES (line 121) | YES (line 24) | YES (line 52) |
| `fs.suid_dumpable: 0` | YES (line 146) | YES (line 170) | YES (line 22) | YES (line 50) |
| `net.ipv6.conf.all.disable_ipv6: 1` | toggle exists (line 43) | YES (line 150) | NO | NO |
| `dev.tty.ldisc_autoload: 0` | YES (line 68) | YES (line 63) | YES (line 18) | NO |
| `vm.unprivileged_userfaultfd: 0` | YES (line 72) | YES (line 68) | YES (line 19) | NO |
| `vm.mmap_min_addr: 65536` | YES (line 76) | YES (line 73) | NO | NO |
| `net.core.bpf_jit_harden: 2` | YES (line 82) | YES (line 81) | YES (line 26) | YES (line 54) |
| `net.ipv4.conf.all.rp_filter: 1` | YES (line 85) | YES (line 88) | NO | NO |
| `net.ipv4.tcp_rfc1337: 1` | YES (line 91) | YES (line 95) | NO | NO |

**Conclusion:** All 11 parameters from GAP-03 are already present in defaults and template. The remaining gap is **test coverage** -- several parameters are verified in the role's own `tasks/verify.yml` but NOT in the molecule `verify.yml`. This is addressed in section 7 below.

### Remaining work for GAP-03

No changes needed to `defaults/main.yml` or `sysctl.conf.j2`. The molecule `verify.yml` must be updated to cover all security parameters (see section 7).

---

## 3. MED-02 Fix Plan: ptrace_scope Default + Per-Parameter Toggle

### Current state

`defaults/main.yml` line 58: `sysctl_kernel_yama_ptrace_scope: 1`

This has **already been fixed** from the original `2` to `1`. The README documents both values and their trade-offs. The role already provides a per-parameter variable (`sysctl_kernel_yama_ptrace_scope`) so users can override to `2` for server hardening.

### Per-parameter toggle design (already exists)

The role already has individual variables for every security parameter. The toggle hierarchy is:

1. `sysctl_security_enabled: false` -- disables ALL security sections
2. `sysctl_security_kernel_hardening: false` -- disables kernel section (ptrace is inside)
3. `sysctl_kernel_yama_ptrace_scope: 1` -- individual value override

No additional toggle work is needed. MED-02 is resolved.

---

## 4. Docker Scenario

### Sysctl limitations in containers

Docker containers share the host kernel. Most sysctl parameters live in the **init namespace** and cannot be written from a container, even with `--privileged`. Specifically:

- **Kernel params** (`kernel.*`): read-only in containers. `sysctl -w kernel.randomize_va_space=2` returns `sysctl: permission denied on key 'kernel.randomize_va_space'` even in privileged mode.
- **Network params** (`net.*`): partly writable if the container has its own network namespace. Parameters under `net.ipv4.conf.all.*` may be writable, but `net.core.*` often are not.
- **fs params** (`fs.*`): `fs.protected_hardlinks`, `fs.protected_symlinks` are read-only. `fs.inotify.*` may be writable.
- **vm params** (`vm.*`): mostly read-only.

**Strategy:** In the docker scenario, the handler that runs `sysctl -e --system` will fail or produce incorrect results. We must:
1. Skip the handler execution (tag the handler trigger or use `--skip-tags`)
2. Test ONLY that the configuration file is deployed correctly (content, ownership, permissions)
3. Do NOT assert live `sysctl -n` values

### Docker scenario: molecule.yml

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
    skip-tags: report,verify
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

**Key decisions:**
- `skip-tags: report,verify` -- skips the role's own `tasks/verify.yml` (which runs `sysctl -n` that would fail) and `tasks/report.yml` (informational only). The role's `tasks/deploy.yml` still runs and the handler still fires, but in a container `sysctl -e --system` will emit errors for unwritable params. Because the handler uses `-e` (ignore errors), it will not fail.
- Actually, the handler running is fine -- `sysctl -e` silently ignores errors for parameters it cannot write. The container will simply not apply them. The template file is still deployed.
- The molecule `verify.yml` (shared) will include a `when` guard to skip live-value assertions in docker (see section 7).

### Docker prepare.yml

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

---

## 5. Vagrant Scenario

### Full verification

In a real VM (KVM via libvirt), all sysctl parameters can be written and read. The vagrant scenario provides full end-to-end testing: deploy the file, apply params, verify live values match.

### Vagrant scenario: molecule.yml

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
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
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

**Key decisions:**
- Two platforms: Arch Linux (`generic/arch`) + Ubuntu 24.04 (`bento/ubuntu-24.04`), matching the project-wide pattern from `package_manager` vagrant scenario
- `skip-tags: report` only -- the role's own `tasks/verify.yml` can run fine in a VM (it reads live values), but molecule's `verify.yml` is the authoritative test
- No `prepare.yml` needed -- vagrant boxes come with working package managers
- No vault password file needed (the sysctl role has no vault-encrypted variables)

---

## 6. Shared Migration Plan

### Directory structure after migration

```
ansible/roles/sysctl/molecule/
  shared/
    converge.yml        # Role application (cross-platform)
    verify.yml          # All assertions (file + live, with when guards)
  docker/
    molecule.yml        # Docker-specific config
    prepare.yml         # pacman -Sy
  vagrant/
    molecule.yml        # Vagrant KVM config
  default/
    molecule.yml        # Keep for local dev (localhost, unchanged)
    converge.yml        # Symlink or redirect to ../shared/converge.yml
    verify.yml          # Symlink or redirect to ../shared/verify.yml
```

### Handling docker/vagrant divergence

The key divergence: docker cannot verify live sysctl values; vagrant can.

**Approach: `when` guards in a single shared verify.yml** (not separate files).

Detection method: check if `/proc/1/cgroup` contains `docker` or if `ansible_virtualization_type == 'docker'`. Ansible's `ansible_virtualization_type` fact reliably reports `docker` inside containers.

```yaml
# In shared/verify.yml
- name: Set container detection fact
  ansible.builtin.set_fact:
    _sysctl_in_container: "{{ ansible_virtualization_type | default('') == 'docker' }}"

# File-level checks run everywhere
- name: Check drop-in file exists
  # ... (always runs)

# Live-value checks skip in containers
- name: Read live vm.swappiness
  ansible.builtin.command: sysctl -n vm.swappiness
  when: not _sysctl_in_container
  # ...
```

This is the same pattern used across the project -- a single `verify.yml` with `when` guards rather than separate verify files per scenario.

### Converge.yml changes

The current `converge.yml` has an assertion: `ansible_facts['os_family'] == 'Archlinux'`. This must be removed for the shared version, since vagrant tests both Arch and Ubuntu. The role itself already has OS-family guards (`when: ansible_facts['os_family'] in _sysctl_supported_os`).

### Default scenario

The `default/` scenario (localhost) should be updated to point to `../shared/converge.yml` and `../shared/verify.yml`, matching the ntp role pattern. If keeping local-only convenience, the `default/molecule.yml` playbook paths change to:

```yaml
playbooks:
  converge: ../shared/converge.yml
  verify: ../shared/verify.yml
```

---

## 7. Verify.yml Design

### Assertions in three tiers

#### Tier 1: File deployment (runs in ALL scenarios including docker)

| Check | Method |
|-------|--------|
| `/etc/sysctl.d/99-ansible.conf` exists | `stat` + assert `exists` |
| File owned by `root:root` | `stat` + assert `pw_name`, `gr_name` |
| File mode `0644` | `stat` + assert `mode` |
| File contains `vm.swappiness` | `slurp` + `b64decode` + assert `in` |
| File contains `kernel.randomize_va_space` (security enabled) | `slurp` + assert `in` |
| File contains `net.ipv4.tcp_syncookies` (network hardening) | `slurp` + assert `in` |
| File contains `fs.protected_hardlinks` (fs hardening) | `slurp` + assert `in` |
| `procps-ng` or `procps` package installed | `package_facts` + assert |
| No IPv6 disable section when `sysctl_security_ipv6_disable: false` | `slurp` + assert `not in` |

#### Tier 2: Live value verification (runs in vagrant + localhost, skips in docker)

**Performance parameters (always set, no toggle):**

| Parameter | Expected | Variable |
|-----------|----------|----------|
| `vm.swappiness` | `10` | `sysctl_vm_swappiness` |
| `vm.vfs_cache_pressure` | `50` | `sysctl_vm_vfs_cache_pressure` |
| `fs.inotify.max_user_watches` | `524288` | `sysctl_fs_inotify_max_user_watches` |
| `fs.inotify.max_user_instances` | `1024` | `sysctl_fs_inotify_max_user_instances` |
| `fs.file-max` | `2097152` | `sysctl_fs_file_max` |
| `net.core.somaxconn` | `4096` | `sysctl_net_core_somaxconn` |
| `net.ipv4.tcp_fastopen` | `3` | `sysctl_net_ipv4_tcp_fastopen` |

**Security: kernel hardening:**

| Parameter | Expected | Notes |
|-----------|----------|-------|
| `kernel.randomize_va_space` | `2` | |
| `kernel.kptr_restrict` | `2` | |
| `kernel.dmesg_restrict` | `1` | |
| `kernel.yama.ptrace_scope` | `1` | |
| `kernel.perf_event_paranoid` | `3` | May return rc=255 on older kernels |
| `kernel.unprivileged_bpf_disabled` | `1` | May return rc=255 on older kernels |
| `dev.tty.ldisc_autoload` | `0` | Kernel 4.7+ |
| `vm.unprivileged_userfaultfd` | `0` | Kernel 5.11+ |
| `vm.mmap_min_addr` | `65536` | |

**Security: network hardening:**

| Parameter | Expected |
|-----------|----------|
| `net.core.bpf_jit_harden` | `2` |
| `net.ipv4.conf.all.rp_filter` | `1` |
| `net.ipv4.tcp_syncookies` | `1` |
| `net.ipv4.tcp_rfc1337` | `1` |
| `net.ipv4.conf.all.accept_redirects` | `0` |
| `net.ipv4.conf.all.send_redirects` | `0` |
| `net.ipv4.conf.all.accept_source_route` | `0` |
| `net.ipv4.conf.all.log_martians` | `1` |
| `net.ipv4.icmp_echo_ignore_broadcasts` | `1` |
| `net.ipv4.icmp_ignore_bogus_error_responses` | `1` |
| `net.ipv4.tcp_timestamps` | `0` |
| `net.ipv4.tcp_tw_reuse` | `0` |
| `net.ipv4.conf.all.arp_filter` | `1` |
| `net.ipv4.conf.all.arp_ignore` | `1` |
| `net.ipv6.conf.all.accept_redirects` | `0` |
| `net.ipv6.conf.all.accept_source_route` | `0` |
| `net.ipv6.conf.all.accept_ra` | `1` |

**Security: filesystem:**

| Parameter | Expected |
|-----------|----------|
| `fs.protected_hardlinks` | `1` |
| `fs.protected_symlinks` | `1` |
| `fs.protected_fifos` | `2` |
| `fs.protected_regular` | `2` |
| `fs.suid_dumpable` | `0` |

#### Tier 3: Cross-platform checks (vagrant only, conditional on distro)

| Check | When | Method |
|-------|------|--------|
| `procps-ng` installed | `ansible_distribution == 'Archlinux'` | `package_facts` |
| `procps` installed | `ansible_os_family == 'Debian'` | `package_facts` |
| `kernel.unprivileged_userns_clone` in config | `ansible_distribution == 'Archlinux'` | `slurp` + assert (Arch-only param) |

### Implementation pattern

The verify.yml will use a loop-based approach for live value checks to avoid 30+ individual tasks:

```yaml
- name: Verify live sysctl values
  ansible.builtin.command: "sysctl -n {{ item.param }}"
  register: _sysctl_verify_live
  changed_when: false
  failed_when: false  # rc=255 means param unsupported
  loop: "{{ _sysctl_verify_params }}"
  loop_control:
    label: "{{ item.param }}"
  when: not _sysctl_in_container

- name: Assert live sysctl values match expected
  ansible.builtin.assert:
    that: item.stdout | string == item.item.expected | string
    fail_msg: "{{ item.item.param }}: expected={{ item.item.expected }} got={{ item.stdout }}"
    success_msg: "{{ item.item.param }}={{ item.stdout }}"
  loop: "{{ _sysctl_verify_live.results }}"
  loop_control:
    label: "{{ item.item.param }}"
  when:
    - not _sysctl_in_container
    - item.rc == 0  # skip unsupported params (rc=255)
```

The params list will be defined as a `vars:` block at the top of verify.yml.

---

## 8. Implementation Order

### Step 1: Fix `_sysctl_supported_os` variable bug

- Create `ansible/roles/sysctl/vars/main.yml` with:
  ```yaml
  ---
  _sysctl_supported_os: "{{ sysctl_supported_os }}"
  ```
- Alternatively, rename in `defaults/main.yml` to use the underscore prefix directly.
- Verify role still runs correctly on localhost.

### Step 2: Create `molecule/shared/` directory

- Create `molecule/shared/converge.yml` -- based on current `default/converge.yml` but WITHOUT the Arch-only assertion (role handles OS guards internally).
- Create `molecule/shared/verify.yml` -- new comprehensive verify with three tiers as designed in section 7.

### Step 3: Update `molecule/default/` to use shared

- Modify `default/molecule.yml` to point playbooks at `../shared/converge.yml` and `../shared/verify.yml`.
- Remove old `default/converge.yml` and `default/verify.yml`.
- Test: `molecule test -s default` on localhost.

### Step 4: Create `molecule/docker/` scenario

- Create `molecule/docker/molecule.yml` per section 4.
- Create `molecule/docker/prepare.yml` (pacman cache update).
- Test: `molecule test -s docker` (requires docker + arch-systemd image).
- Verify: file-level checks pass, live-value checks are skipped.

### Step 5: Create `molecule/vagrant/` scenario

- Create `molecule/vagrant/molecule.yml` per section 5.
- Test: `molecule test -s vagrant` (requires libvirt + vagrant).
- Verify: both file-level and live-value checks pass on both Arch and Ubuntu.

### Step 6: Verify idempotence

- Both docker and vagrant scenarios include `idempotence` in test_sequence.
- The template task should show `changed` on first run, `ok` on second run.
- The handler must not fire on the second run (no changes to template).

### Step 7: CI integration

- Add sysctl to the existing molecule-docker CI workflow (or create one).
- Add sysctl to the molecule-vagrant CI workflow if it exists.
- Ensure tags skip correctly in CI context.

---

## 9. Risks / Notes

### Sysctl in containers -- namespace restrictions

| Namespace | Writable in `--privileged` container? | Notes |
|-----------|:---:|-------|
| `kernel.*` | NO | Init namespace only |
| `net.core.*` | SOMETIMES | Depends on network namespace isolation |
| `net.ipv4.conf.*` | YES (own netns) | Container gets its own network namespace |
| `net.ipv6.conf.*` | YES (own netns) | Same as above |
| `fs.*` | NO | Shared with host |
| `vm.*` | NO | Shared with host |

The handler runs `sysctl -e --system` which ignores write errors (`-e`). The container will silently skip unwritable params. This means idempotence checking is safe -- the template file does not change, so the handler does not fire on the second converge run.

### Privileged mode required for docker

The arch-systemd container already uses `privileged: true` for systemd. No additional configuration needed for the sysctl role's deploy tasks (file creation only needs filesystem access, which is available in any container).

### Kernel version sensitivity

Several security parameters require specific minimum kernel versions:
- `dev.tty.ldisc_autoload` -- kernel 4.7+
- `vm.unprivileged_userfaultfd` -- kernel 5.11+
- `kernel.perf_event_paranoid: 3` -- kernel 4.6+ (value `3` specifically)
- `kernel.unprivileged_bpf_disabled` -- kernel 4.4+

The `generic/arch` vagrant box and `bento/ubuntu-24.04` both ship kernels >= 6.x, so all parameters are supported. The verify.yml handles older kernels via `when: item.rc == 0` (skips params that return rc=255 from `sysctl -n`).

### The `sysctl_security_ipv6_disable` toggle

Default is `false`. The verify.yml should assert that when the toggle is `false`, the disable_ipv6 directives are NOT present in the config file. When the toggle is `true`, they should be present. Since molecule runs with defaults, the test confirms the `false` path. A separate test with overridden vars could test the `true` path, but this is lower priority.

### No vault dependency

The sysctl role has no vault-encrypted variables. The `default/molecule.yml` currently includes `vault_password_file` (inherited from template), but it is not required. The docker and vagrant scenarios omit it.

### `_sysctl_supported_os` bug severity

If this bug is live in production, the role silently does nothing on any host. This should be validated immediately and is the highest-priority fix, before any molecule work. Run `ansible-playbook playbook.yml --tags sysctl --check -v` against a target to confirm whether the role executes.

### Template has no `validate:` parameter

The `deploy.yml` template task does not use `validate:` to check the generated config. While sysctl config files have a simple `key = value` format and Jinja2 errors would cause Ansible to fail at template rendering time, adding basic validation is a nice-to-have:
```yaml
validate: 'sysctl -e -p %s'
```
This is out of scope for the molecule plan but noted for follow-up.
