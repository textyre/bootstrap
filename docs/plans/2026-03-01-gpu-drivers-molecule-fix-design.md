# gpu_drivers molecule test fix — Design

**Date:** 2026-03-01
**Status:** Approved
**Scope:** Fix molecule tests for `gpu_drivers` role so all 3 CI environments pass (Docker Arch, Docker Ubuntu, Vagrant Arch, Vagrant Ubuntu).

## Context

The `gpu_drivers` role has molecule tests (docker + vagrant scenarios) written in commit `2228bc8` but never run in GHA. Two confirmed bugs and one inconsistency were found via static analysis.

## Confirmed Bugs

### Bug 1 — `initramfs.yml:23` — undefined variable (CRITICAL)

Task `Check if dracut is available` registers result as `gpu_drivers_dracut_check`.
Task `Set initramfs tool fact` references `_gpu_drivers_dracut_check` (extra underscore).

On Ubuntu/Debian with `gpu_drivers_manage_initramfs: true` (default), `Set initramfs tool fact` runs and evaluates `_gpu_drivers_dracut_check is not skipped` — undefined variable → Ansible error.

On Arch the expression short-circuits to `mkinitcpio` before evaluating the undefined variable, so no failure there.

**Fix:** Remove underscore prefix in `Set initramfs tool fact` — use `gpu_drivers_dracut_check` everywhere.

### Bug 2 — `docker/prepare.yml` — Ubuntu pciutils not installed

`prepare.yml` installs pciutils only for Arch via `community.general.pacman`. Ubuntu is not covered. It currently works incidentally because `converge.yml` installs pciutils via `ansible.builtin.package` before the role runs, but this creates an inconsistency: prepare is supposed to set up prerequisites.

**Fix:** Add an `ansible.builtin.apt` task for Ubuntu in `docker/prepare.yml`, matching the pattern in `vagrant/prepare.yml`.

## Test Strategy

- Vendor override: `gpu_drivers_vendor: intel` (pure Mesa, no DKMS, no kernel modules — fully testable in Docker)
- All 4 test runners: Docker-Arch, Docker-Ubuntu, Vagrant-Arch, Vagrant-Ubuntu
- Test sequence: `syntax → create → prepare → converge → idempotence → verify → destroy`

## Files Changed

| File | Change |
|------|--------|
| `ansible/roles/gpu_drivers/tasks/initramfs.yml` | Fix variable name: `_gpu_drivers_dracut_check` → `gpu_drivers_dracut_check` |
| `ansible/roles/gpu_drivers/molecule/docker/prepare.yml` | Add `ansible.builtin.apt` block for Ubuntu pciutils |

## Success Criteria

All 3 CI jobs green in GHA:
1. `test / gpu_drivers` (Docker, both Arch + Ubuntu platforms)
2. `test-vagrant / gpu_drivers / arch-vm`
3. `test-vagrant / gpu_drivers / ubuntu-base`
