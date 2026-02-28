# Design: vm role — molecule tests in 3 environments

**Date:** 2026-02-28
**Status:** Approved

## Problem

The `vm` role has only a `molecule/default/` scenario with a **delegated driver** (runs against localhost — a real VirtualBox VM). The CI detection job scans for `molecule/docker/molecule.yml` to include a role in Docker CI, and `molecule/vagrant/molecule.yml` for Vagrant CI. Neither exists, so the `vm` role is invisible to all CI.

Additionally, two `register:` naming bugs in role task files cause failures in any environment where `vm_is_guest` is true (Vagrant/KVM path), making Vagrant tests non-functional even if the scenarios existed.

## Goal

- Tests pass in 3 CI environments: Docker, Vagrant Arch (arch-vm), Vagrant Ubuntu (ubuntu-base)
- Merged feature branch

## Approach: Full shared/docker/vagrant restructure

Mirrors the established `pam_hardening` pattern. Keeps `default/` intact for local use.

## File structure

```
ansible/roles/vm/molecule/
├── default/            # existing — delegated/localhost, unchanged
│   ├── molecule.yml
│   ├── prepare.yml
│   ├── converge.yml
│   └── verify.yml
├── shared/             # NEW
│   ├── converge.yml    # apply vm role, no vault refs
│   └── verify.yml      # handles container + KVM environments
├── docker/             # NEW — enables Docker CI
│   ├── molecule.yml    # Arch-systemd + Ubuntu-systemd platforms
│   └── prepare.yml     # OS-conditional cache update
└── vagrant/            # NEW — enables Vagrant CI
    ├── molecule.yml    # arch-vm + ubuntu-base platforms
    └── prepare.yml     # Arch keyring+sysupgrade, apt update
```

## Role bug fixes

Two `register:` naming inconsistencies where the `_` prefix is missing from `register:` but present in all callers.

### `tasks/_install_packages.yml`

```yaml
# Before (broken — callers including until: reference _vm_pkg_install_result)
register: vm_pkg_install_result
until: _vm_pkg_install_result is succeeded

# After
register: _vm_pkg_install_result
until: _vm_pkg_install_result is succeeded
```

Callers that reference `_vm_pkg_install_result`: `until:` condition in the same task, `_reboot_flag.yml` conditions.

### `tasks/_manage_services.yml`

```yaml
# Before (broken — failed_when and report tasks reference _vm_svc_result)
register: vm_svc_result
failed_when:
  - _vm_svc_result is failed

# After
register: _vm_svc_result
failed_when:
  - _vm_svc_result is failed
```

**Impact:** Docker tests are unaffected (container env → `vm_is_guest` = false → these code paths skipped). Vagrant tests require both fixes to pass.

## Shared verify.yml logic

No `vars_files` references. No cross-play `vm_reboot_required` assertion (set_fact, not disk-persisted).

### Docker (container environment)

- `virtualization_type` = `container`
- `vm_is_guest` = false → role skips all package installs
- Assert: `/etc/ansible/facts.d/vm_guest.fact` does **not** exist
- Assert: role ran without error (facts module populated)

### Vagrant KVM (arch-vm, ubuntu-base)

- `virtualization_type` = `kvm`, `vm_is_guest` = true
- Role installs `qemu-guest-agent`, enables service, writes fact file
- Assert: `qemu-guest-agent` service is active
- Assert: fact file exists with `hypervisor: kvm` and `is_guest: true`

## CI integration

No workflow changes needed. The existing `molecule.yml` auto-detects:
- Docker CI: triggered by presence of `molecule/docker/molecule.yml`
- Vagrant CI: triggered by presence of `molecule/vagrant/molecule.yml` (both arch-vm + ubuntu-base platforms run in parallel)

## Scope

| File | Action |
|------|--------|
| `roles/vm/tasks/_install_packages.yml` | Fix `register:` naming bug |
| `roles/vm/tasks/_manage_services.yml` | Fix `register:` naming bug |
| `roles/vm/molecule/shared/converge.yml` | Create |
| `roles/vm/molecule/shared/verify.yml` | Create |
| `roles/vm/molecule/docker/molecule.yml` | Create |
| `roles/vm/molecule/docker/prepare.yml` | Create |
| `roles/vm/molecule/vagrant/molecule.yml` | Create |
| `roles/vm/molecule/vagrant/prepare.yml` | Create |
