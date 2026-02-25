# hostname: Vagrant KVM Molecule Scenario -- Plan

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### Role purpose

The `hostname` role does two things:

1. Sets the system hostname via `ansible.builtin.hostname` (strategy selected per OS family from `vars/main.yml`).
2. Manages the `127.0.1.1` entry in `/etc/hosts` with optional FQDN (`hostname_domain`).

Both steps include inline verification (assert hostname matches, grep hosts file) and reporting via the `common` role.

### Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `hostname_name` | `""` (assert fails) | Required. Static hostname. |
| `hostname_domain` | `""` | Optional. Appended as FQDN: `host.domain\thost` |

`vars/main.yml` maps `ansible_facts['os_family']` to a hostname strategy:

| OS Family | Strategy |
|-----------|----------|
| Archlinux | `systemd` |
| Debian | `debian` |
| RedHat | `redhat` |
| Alpine | `alpine` |
| Void | `generic` |

### Existing molecule scenarios

```
molecule/
  shared/
    converge.yml   -- applies role with hostname_name="archbox", hostname_domain="example.com"
    verify.yml     -- 4 checks (see below)
  default/
    molecule.yml   -- driver: default (localhost), no create/destroy
  docker/
    molecule.yml   -- driver: docker, arch-systemd image, privileged
    prepare.yml    -- unmounts Docker bind-mounted /etc/hostname and /etc/hosts
```

### shared/converge.yml

Applies the role once with fixed test values:
- `hostname_name: "archbox"`
- `hostname_domain: "example.com"`

No vault files. No arch-only assertions. No `vars_files`.

### shared/verify.yml

Four checks, all OS-agnostic:

1. **Hostname exact match** -- `hostnamectl status --static` stdout == `"archbox"`.
2. **FQDN in /etc/hosts** -- slurp `/etc/hosts`, assert contains `127.0.1.1`, `archbox.example.com`, `archbox`.
3. **No duplicate 127.0.1.1** -- regex_findall count == 1.
4. **Summary debug** -- prints result.

### docker/prepare.yml

Docker bind-mounts `/etc/hostname` and `/etc/hosts` from the host, which breaks atomic rename operations used by `hostnamectl` and `lineinfile`. The prepare playbook `umount`s both files to make them regular overlay-fs files.

This is Docker-specific and **not needed** for Vagrant VMs.

## 2. Cross-Platform Analysis

The hostname role is one of the simplest roles to test cross-platform. Both Arch and Ubuntu use systemd, so the core operations are nearly identical.

### What is identical (Arch and Ubuntu)

| Aspect | Arch Linux | Ubuntu 24.04 | Notes |
|--------|------------|--------------|-------|
| `/etc/hostname` | Present | Present | Both use systemd-hostnamed |
| `hostnamectl` | Available | Available | Both systemd-based |
| `/etc/hosts` | Present, writable | Present, writable | Standard file |
| `127.0.1.1` convention | Supported | Supported (default in Ubuntu) | Ubuntu installers typically pre-populate this line |
| `lineinfile` behavior | Works | Works | Same file format |
| `hostname` module | strategy: `systemd` | strategy: `debian` | Different strategy, same result |
| Python | May need install | Pre-installed | Vagrant `generic/arch` may lack Python |

### Differences that matter

1. **Hostname module strategy**: Arch uses `systemd`, Ubuntu uses `debian`. The role already handles this via `vars/main.yml` mapping. No changes needed.

2. **Pre-existing `127.0.1.1` line**: Ubuntu boxes often ship with a `127.0.1.1` line containing the box's original hostname. The `lineinfile` task uses `regexp: '^127\.0\.1\.1'` which replaces in-place. This is correct behavior -- the test expects exactly one `127.0.1.1` line and it will pass.

3. **Python availability on Arch**: The `generic/arch` Vagrant box may not have Python pre-installed. The prepare playbook must bootstrap Python before `gather_facts`.

### verify.yml cross-platform compatibility

All four checks in `shared/verify.yml` are fully OS-agnostic:

- `hostnamectl status --static` -- works on both (both are systemd).
- `slurp /etc/hosts` -- works on both (same file path).
- String assertions -- no OS-specific logic.
- No `when:` guards needed.

**Verdict: shared/verify.yml requires zero modifications for Ubuntu support.**

### converge.yml cross-platform compatibility

The converge playbook uses `hosts: all` with `gather_facts: true`. The role internally dispatches to the correct hostname strategy via `vars/main.yml`. The test values (`archbox`, `example.com`) are syntactically valid hostnames on any OS.

**Verdict: shared/converge.yml requires zero modifications for Ubuntu support.**

## 3. Vagrant Scenario

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

**Design decisions:**

- `skip-tags: report` -- the `common` role report tasks are not relevant in molecule and would require the `common` role to be present. Skipping avoids a dependency.
- `memory: 2048` / `cpus: 2` -- consistent with `package_manager` vagrant scenario. The hostname role is lightweight; 1024 MB would suffice, but 2048 is the project standard.
- Box choices: `generic/arch` and `bento/ubuntu-24.04` match the template specification. Both support libvirt provider.
- No `inventory.host_vars` for localhost python interpreter -- not needed because vagrant scenarios SSH into real VMs (unlike default scenario which runs on localhost).

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

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**This is identical to `package_manager/molecule/vagrant/prepare.yml`** and covers the two critical Vagrant box bootstrapping needs:

1. **Python on Arch**: The `generic/arch` box may not have Python. Ansible requires Python for all modules except `raw`. The `raw` task installs Python before `gather_facts`.

2. **Stale pacman keyring**: The `generic/arch` box ships with a keyring snapshot from build time. Package signature verification fails on rolling-release updates. The workaround temporarily disables SigLevel, updates the keyring, then re-enables verification.

3. **Ubuntu apt cache**: Refresh the package index so any packages installed later (if needed) resolve correctly. The hostname role does not install packages, but this is defensive and consistent with the project pattern.

The full system upgrade on Arch (`pacman -Syu`) ensures library compatibility. While the hostname role itself does not install packages, `hostnamectl` depends on system libraries that could be mismatched in a stale box image.

## 4. Shared verify.yml Cross-Platform Fixes

**None required.**

The existing `shared/verify.yml` is fully cross-platform:

| Check | Command/Module | Arch | Ubuntu | Cross-platform? |
|-------|---------------|------|--------|-----------------|
| Get hostname | `hostnamectl status --static` | Yes (systemd) | Yes (systemd) | Yes |
| Assert hostname | String comparison | OS-agnostic | OS-agnostic | Yes |
| Read /etc/hosts | `slurp /etc/hosts` | Same path | Same path | Yes |
| Assert FQDN entry | String `in` check | OS-agnostic | OS-agnostic | Yes |
| Assert no duplicate | regex_findall | OS-agnostic | OS-agnostic | Yes |

No `when: ansible_facts['os_family']` guards are needed anywhere in the verify playbook.

**Potential edge case (informational, no action needed):** Ubuntu boxes may ship with a pre-existing `127.0.1.1` line (e.g., `127.0.1.1 ubuntu-noble ubuntu-noble`). The role's `lineinfile` task uses `regexp: '^127\.0\.1\.1'` which matches and replaces this line. The verify check for exactly one `127.0.1.1` line will pass because `lineinfile` replaces rather than appends when the regexp matches.

## 5. Implementation Order

1. **Create `molecule/vagrant/molecule.yml`** -- copy the YAML from section 3 above.

2. **Create `molecule/vagrant/prepare.yml`** -- copy the YAML from section 3 above (identical to `package_manager` vagrant prepare).

3. **Smoke test locally** (if KVM is available):
   ```bash
   cd ansible/roles/hostname
   molecule test -s vagrant
   ```
   Expected: all 7 steps pass (syntax, create, prepare, converge, idempotence, verify, destroy).

4. **Verify idempotence** -- the hostname role should produce zero changes on second run. Both `ansible.builtin.hostname` (when hostname already matches) and `lineinfile` (when line already present) are idempotent. Confirm molecule's idempotence check passes on both platforms.

5. **Commit** -- single commit adding the two new files:
   - `ansible/roles/hostname/molecule/vagrant/molecule.yml`
   - `ansible/roles/hostname/molecule/vagrant/prepare.yml`

## 6. Risks / Notes

### Low risk

- **Stale Arch box**: The `generic/arch` box is community-maintained. If the box becomes unavailable or severely outdated, the pacman keyring workaround in `prepare.yml` handles most staleness. If the box is completely broken, switch to `archlinux/archlinux` (official Arch box).

- **Ubuntu pre-existing hostname**: Ubuntu boxes ship with a hostname already set. The role overwrites it. This is expected behavior and the verify checks validate the final state, not the transition.

### No risk

- **Shared playbook compatibility**: No changes to `shared/converge.yml` or `shared/verify.yml` are needed. The vagrant scenario purely adds a new scenario directory alongside the existing `default/` and `docker/` scenarios.

- **Docker scenario unaffected**: The Docker scenario continues to work as-is. Its `prepare.yml` (umount bind mounts) is Docker-specific and lives in `molecule/docker/`.

### Notes

- The `skip-tags: report` option means the `common` role does not need to be present in `ANSIBLE_ROLES_PATH` during vagrant testing. The reporting tasks are skipped entirely. This is consistent with the Docker scenario.

- The hostname role has no package installation tasks, no service management, and no template rendering. It is purely `hostnamectl` + `lineinfile`. This makes it one of the lowest-risk roles to test under Vagrant.

- No CI workflow file (`.github/workflows/molecule-vagrant.yml`) is included in this plan. The vagrant scenario is assumed to be picked up by an existing or future centralized vagrant workflow, or run manually with `molecule test -s vagrant`. Creating the CI workflow is out of scope for this plan.

## File Summary

Two new files to create:

| File | Purpose |
|------|---------|
| `ansible/roles/hostname/molecule/vagrant/molecule.yml` | Vagrant/libvirt driver config for Arch + Ubuntu VMs |
| `ansible/roles/hostname/molecule/vagrant/prepare.yml` | Python bootstrap (Arch), keyring refresh, apt cache update |

Zero files modified.
