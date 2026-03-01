# power_management molecule test fix — Design

**Date:** 2026-03-01
**Status:** Approved
**Scope:** Fix molecule tests for `power_management` role so all 3 CI environments pass (Docker Arch+Ubuntu, Vagrant Arch, Vagrant Ubuntu).

## Context

The `power_management` role has molecule tests (docker + vagrant scenarios) that are included in the CI matrix but have never passed. Two categories of confirmed bugs found via static analysis.

## Confirmed Bugs

### Bug 1 — `handlers/main.yml:21` — `Reload udev rules` lacks `failed_when: false` (CRITICAL)

`udevadm control --reload-rules` is called without a `failed_when: false` guard.

In Docker containers (even privileged ones), `systemd-udevd` may not be running — it either fails to start or is masked by systemd's container detection. The command returns non-zero → the handler fails → the **entire converge play fails** before verify even runs.

This handler is always triggered on the first run because `50-cpu-governor.rules` is always deployed fresh.

**Fix:** Add `failed_when: false` to the handler. The udev rule file is deployed correctly regardless; the reload is a best-effort operation that will take effect on the next udevd trigger or reboot.

### Bug 2 — `handlers/main.yml:12` — `Reload systemd-logind` lacks `failed_when: false` (CRITICAL)

`systemctl reload systemd-logind` is called without a `failed_when: false` guard.

In Docker containers, logind may not be running (it requires a proper VT/seat) or may reject a reload. Same failure path as Bug 1 — hard crash in the handler phase.

This handler is always triggered on the first run because `logind.conf` is always deployed fresh.

**Fix:** Add `failed_when: false` to the handler. The logind.conf file is deployed correctly; the reload is best-effort.

### Bug 3 — `molecule/vagrant/prepare.yml` — Arch has no preparation (HIGH)

The vagrant `prepare.yml` only loads cpufreq kernel modules and updates the apt cache (Ubuntu). **Arch gets no preparation at all** — no `pacman update_cache`, no keyring refresh, no full system upgrade, no DNS fix.

When `install-archlinux.yml` runs `pacman -S cpupower`, the package database is stale → installation may fail with GPG signature errors or "file not found" on outdated mirrors.

The established pattern (from `vm` role's `molecule/vagrant/prepare.yml`, confirmed working in CI) requires:
1. `gather_facts: false`
2. Raw Python install (arch-base box ships Python, but explicit bootstrap is safe)
3. `setup` module to gather facts
4. Keyring refresh via `SigLevel=Never` trick
5. Full `pacman -Syu` upgrade
6. DNS fix after upgrade (systemd stubs replace resolv.conf)

**Fix:** Rewrite `molecule/vagrant/prepare.yml` using the vm role's established pattern, keeping the cpufreq module loading at the end.

## Files Changed

| File | Change |
|------|--------|
| `ansible/roles/power_management/handlers/main.yml` | Add `failed_when: false` to both handlers |
| `ansible/roles/power_management/molecule/vagrant/prepare.yml` | Full rewrite: Arch bootstrap + cpufreq modules |

## Test Strategy

- Docker scenario: Arch-systemd + Ubuntu-systemd platforms (both in one job)
- Vagrant scenario: arch-vm + ubuntu-base (separate jobs, parallel matrix)
- Test sequence: `syntax → create → prepare → converge → idempotence → verify → destroy`
- Converge vars: `power_management_device_type: desktop`, `power_management_assert_strict: false`, `power_management_audit_battery: false`

## Success Criteria

All 3 CI jobs green in GHA:
1. `test / power_management` (Docker, Arch-systemd + Ubuntu-systemd)
2. `test-vagrant / power_management / arch-vm`
3. `test-vagrant / power_management / ubuntu-base`
