# sysctl molecule tests fix — design

**Date:** 2026-03-01
**Goal:** Pass molecule tests in all 3 environments: Docker (Arch+Ubuntu), Vagrant arch-vm, Vagrant ubuntu-base.

## Root Causes

### Docker failure (primary)

`handlers/main.yml` runs `sysctl -e --system` on every config change. The `-e` flag suppresses only "unknown key" errors (ENOENT), not permission errors (EPERM). Inside a Docker container — even with `privileged: true` — kernel-namespace parameters (`kernel.randomize_va_space`, `kernel.kptr_restrict`, etc.) are read-only. The handler exits non-zero → converge fails.

The verify.yml already correctly skips Tier 2 live value checks in containers via `ansible_virtualization_type == 'docker'`. The handler needs the same treatment.

### Vagrant gap (minor)

`molecule/vagrant/prepare.yml` is absent. All other roles with vagrant scenarios follow the pattern of having a prepare.yml that updates the package cache. The absence is a consistency gap; the custom boxes have pre-installed packages but may have stale package indexes.

## Approach

**Option A** — `failed_when: false` on handler: masks errors on real systems too.
**Option B (chosen)** — `when: ansible_virtualization_type | default('') != 'docker'` on handler + add vagrant/prepare.yml.

Rationale for Option B: uses the exact same container-detection pattern already in verify.yml. On Docker the handler is skipped (nothing to apply anyway). On Vagrant VMs the handler runs normally and any real failure is surfaced. Minimal and semantically correct.

## Changes

### 1. `ansible/roles/sysctl/handlers/main.yml`

Add `when: ansible_virtualization_type | default('') != 'docker'`:

```yaml
- name: Apply sysctl settings
  listen: "reload sysctl"
  ansible.builtin.command: sysctl -e --system
  changed_when: false
  when: ansible_virtualization_type | default('') != 'docker'
```

Result: handler silently skips in Docker; runs normally on Vagrant VMs.

### 2. `ansible/roles/sysctl/molecule/vagrant/prepare.yml` (new file)

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

## No other changes needed

- `shared/verify.yml` Tier 1/2/3 already handles Docker/Vagrant correctly
- Package installation (`procps`/`procps-ng`) works in all environments
- Template and config deployment are environment-agnostic
- `kernel.unprivileged_userns_clone` is always written to config (sysctl -e silently ignores on standard kernels); Tier 3 check validates config content, not live value

## Test strategy

Push to `fix/sysctl-molecule-tests` branch. CI (`molecule.yml`) triggers Docker test automatically on PR. Vagrant test triggered via `workflow_dispatch` (`molecule-vagrant.yml`) for both platforms.
