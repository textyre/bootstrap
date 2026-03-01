# Design: User Role Molecule Test Hardening

**Date:** 2026-03-01
**Status:** Approved

## Problem

The `user` role has molecule tests for three CI environments:

- Docker (Arch + Ubuntu systemd containers)
- Vagrant arch-vm (arch-base box via libvirt)
- Vagrant ubuntu-base (ubuntu-base box via libvirt)

Tests likely fail due to infrastructure gaps in prepare.yml files,
not role logic errors.

## Root Causes

| # | Problem | Location | Severity |
|---|---------|----------|----------|
| 1 | `video` group not created before converge — `ansible.builtin.user` fails if group absent | docker/prepare.yml, vagrant/prepare.yml | Critical |
| 2 | `logrotate` only installed for Arch in vagrant prepare — Ubuntu skipped | vagrant/prepare.yml | Critical |
| 3 | No `update_cache` before Arch package install in vagrant prepare | vagrant/prepare.yml | Moderate |
| 4 | `user_manage_password_aging: false` in shared converge — VMs can support full testing | shared/converge.yml | Moderate |

## Solution

Scope: molecule/ only — role tasks untouched.

### Fix 1 — docker/prepare.yml

Add explicit `video` group creation (idempotent):

```yaml
- name: Ensure video group exists (for testuser_extra)
  ansible.builtin.group:
    name: video
    state: present
```

### Fix 2 — vagrant/prepare.yml

Restructure to:
- Run `update_cache` for Arch before installing packages
- Install `logrotate` for both Arch and Ubuntu
- Create `video` group for both platforms

### Fix 3 — vagrant/converge.yml (new file)

Vagrant-specific converge overriding shared defaults for full VM coverage:

```yaml
user_manage_password_aging: false  # chage may not work in libvirt VMs without full PAM
user_verify_root_lock: false       # vagrant boxes don't lock root
```

Update `vagrant/molecule.yml` → `playbooks.converge: converge.yml`

### Fix 4 — verify.yml

No changes required. Current shared/verify.yml is cross-platform correct.

## CI Flow After Fix

```
PR opened with ansible/roles/user/** changes
  → molecule.yml detect job runs
  → Docker test: Arch-systemd + Ubuntu-systemd (parallel)
  → Vagrant test: arch-vm platform
  → Vagrant test: ubuntu-base platform
All 4 pass → PR mergeable
```

## Out of Scope

- Role task changes
- Adding new verify assertions
- Password aging verification (chage in libvirt VM is complex, deferred)
