# ssh_keys Molecule Test Fix — Design

**Date:** 2026-03-01
**Author:** Claude Sonnet 4.6
**Status:** Approved

## Problem

The `ssh_keys` role has molecule scenarios (docker + vagrant + default) that were
written in commit `341d65a` but have never been triggered in GHA. The tests are
untested — we need to verify them green in all 3 CI environments: Docker
(Arch+Ubuntu), Vagrant Arch, and Vagrant Ubuntu.

## Analysis

### Identified issues (code review)

1. **`default/molecule.yml` — typo in test_sequence**: `idempotency` (invalid) must be
   `idempotence`. Molecule does not recognise the misspelled step name.

2. **`vagrant/prepare.yml` — missing Arch pacman cache update**: The gpu_drivers and
   package_manager vagrant prepare files both call `community.general.pacman:
   update_cache: true` for Arch. The ssh_keys vagrant prepare skips this, which can
   cause "too old" metadata errors on the arch-base Vagrant box.

3. **Tests otherwise correct**: Cross-platform OS guards in docker/prepare.yml are
   present; shared/converge.yml and shared/verify.yml have correct logic for
   testuser key injection, absent_user cleanup, and file-permission assertions.

### GHA test matrix

| Environment | Workflow | Scenario |
|-------------|----------|----------|
| Docker (Arch+Ubuntu) | `_molecule.yml` | `docker` |
| Vagrant Arch | `_molecule-vagrant.yml` | `vagrant --platform-name arch-vm` |
| Vagrant Ubuntu | `_molecule-vagrant.yml` | `vagrant --platform-name ubuntu-base` |

## Changes

### 1. Fix `default/molecule.yml` typo

```yaml
# Before
- idempotency
# After
- idempotence
```

### 2. Add Arch pacman cache update to `vagrant/prepare.yml`

Add before the user-creation tasks, following the gpu_drivers pattern:

```yaml
- name: Update pacman package cache (Arch)
  community.general.pacman:
    update_cache: true
  when: ansible_facts['os_family'] == 'Archlinux'
```

## Workflow

1. Create git worktree → branch `fix/ssh-keys-molecule-tests`
2. Apply 2 changes above
3. Push → open PR → GHA runs all 3 environments automatically
4. If all green → merge PR → delete worktree
5. If failures → diagnose → fix → push until green

## Success criteria

- `test (ssh_keys) / ssh_keys (Arch+Ubuntu/systemd)` → success
- `test-vagrant (ssh_keys, arch-vm) / ssh_keys — arch-vm` → success
- `test-vagrant (ssh_keys, ubuntu-base) / ssh_keys — ubuntu-base` → success
- PR merged, branch deleted, worktree removed
