# pam_hardening: Test Fix Design

**Date:** 2026-02-28
**Status:** Approved

## Problem

Two issues block pam_hardening tests from passing in CI:

### 1. Docker test: pacman on Ubuntu (code bug)

`molecule/docker/prepare.yml` runs `community.general.pacman` unconditionally on all containers. The docker scenario has both `Archlinux-systemd` and `Ubuntu-systemd` platforms. Ubuntu has no `pacman` binary → fatal error during prepare step.

**Error:**
```
fatal: [Ubuntu-systemd]: FAILED! => {"msg": "Failed to find required executable \"pacman\""}
```

### 2. Vagrant molecule.yml misalignment (cleanup)

`molecule/vagrant/molecule.yml` has:
- An `inventory.host_vars.localhost.ansible_python_interpreter` block not present in other working roles
- Missing `options: skip-tags: report` in provisioner (present in all other passing vagrant roles)

### 3. "Only run when changed" — already correct

The `detect` job in `.github/workflows/molecule.yml` uses `tj-actions/changed-files` to build role matrices and only runs tests for changed roles. No changes required.

## Solution

### Approach: Minimal targeted fix (A)

Fix only the two files that have actual issues. No CI workflow changes.

## Changes

### File 1: `ansible/roles/pam_hardening/molecule/docker/prepare.yml`

- Change `gather_facts: false` → `gather_facts: true`
- Replace unconditional `community.general.pacman` task with two conditional tasks:
  - `community.general.pacman: update_cache: true` when `ansible_facts['os_family'] == 'Archlinux'`
  - `ansible.builtin.apt: update_cache: true, cache_valid_time: 3600` when `ansible_facts['os_family'] == 'Debian'`

This mirrors the already-correct pattern in `molecule/vagrant/prepare.yml`.

### File 2: `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml`

- Remove `inventory.host_vars.localhost.ansible_python_interpreter` block
- Add `options: skip-tags: report` to provisioner

Aligns with the standard pattern used in fail2ban, locale, git, ntp, and all other working vagrant roles.

## What is NOT changed

- Role tasks (correct)
- Shared `converge.yml` / `verify.yml` (correct)
- CI workflows (detect/change logic already correct)
- `molecule/vagrant/prepare.yml` (already handles both OS families correctly)

## Validation

After merge, CI should show:
- `test (pam_hardening)` (Docker) — passes both Archlinux-systemd and Ubuntu-systemd
- `test-vagrant (pam_hardening, arch-vm)` — already passes, continues to pass
- `test-vagrant (pam_hardening, ubuntu-base)` — passes (was flaky due to unrelated CI runner issue; may need a retry if runner has KVM trouble)
