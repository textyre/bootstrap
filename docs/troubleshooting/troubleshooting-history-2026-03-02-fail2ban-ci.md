# Troubleshooting: fail2ban Molecule CI Failures

**Date:** 2026-03-02
**Branch:** ci/track-fail2ban
**PR:** #53
**Status:** Resolved

---

## Problem

Three distinct CI failures in the fail2ban role:

1. **Docker — iptables-nft conflict**: `pacman -S iptables-nft` failed because `iptables` is already installed and `iproute2` depends on `libxtables.so=12-64` (provided by both).
2. **Docker — idempotence (`changed=1`)**: `Enable and start fail2ban` changed on second converge because fail2ban crashes in Docker containers on every start (netfilter/iptables unavailable).
3. **Vagrant/arch — fail2ban never starts**: socket `/var/run/fail2ban/fail2ban.sock` never created; assert fails after 5 retries.

---

## Root Cause Analysis

### Issue 1: iptables-nft conflict (Docker prepare)

`iproute2` depends on `libxtables.so=12-64`. Removing `iptables` alone breaks `iproute2`. The fix: install `iptables-nft` with `--ask=4` (ALPM_QUESTION_CONFLICT_PKG) to auto-confirm the replacement in a **single transaction**, keeping `iproute2` satisfied because `iptables-nft` also provides `libxtables.so=12-64`.

### Issue 2: Docker idempotence (`changed=1`)

**Root cause:** fail2ban cannot start in Docker containers. The default banaction `iptables-multiport` tries to run `iptables -N` (actionstart) during jail initialization. In Docker, even privileged containers on GitHub Actions runners, these netfilter operations fail or cause fail2ban to crash before creating its socket.

**Failed approaches:** `banaction = noop` (added to group_vars) did not fix the crash — fail2ban crashed before socket creation regardless of banaction. The `ansible_virtualization_type` guard in verify.yml skipped the assertion but didn't fix the idempotence issue (service kept getting started and crashing).

**Working fix:** Follow the `firewall` role pattern — add `fail2ban_start_service: true` variable (default) and skip the service start in Docker with `extra-vars: "fail2ban_start_service=false"`. This separates "enable the service for autostart" (always) from "start it now" (only in real environments).

**Second bug found:** Splitting `enabled: true` and `state: started` into separate tasks revealed that on Arch Linux, `pacman install fail2ban` does NOT auto-enable the service (unlike Ubuntu's apt which runs post-install scripts). The combined task was skipped entirely when `fail2ban_start_service=false`, leaving the service `disabled`. Fix: unconditional "Enable fail2ban" task + conditional "Start fail2ban" task.

### Issue 3: Vagrant/arch fail2ban crash

**Root cause:** fail2ban crashed before creating its socket on the Arch vagrant VM. With `backend = auto`, fail2ban tries to import `python-systemd` for the systemd journal backend. In the specific Arch vagrant box + kernel combination used in CI, this import or its initialization causes fail2ban to die before socket creation.

**Evidence:** Socket never appeared even after 12 seconds (5 retries × 2s). `systemctl start fail2ban` returned 0 (Type=simple, process started from systemd's perspective), but the socket was never created. Ubuntu vagrant worked fine because it uses pyinotify with `/var/log/auth.log`.

**Fix:** Set `fail2ban_sshd_backend: polling` for `arch-vm` via molecule `host_vars`. The polling backend doesn't import python-systemd at all, bypassing the crash. Also create a dummy `/var/log/auth.log` in prepare.yml (Arch has no syslog by default; polling backend needs the file to exist).

---

## Changes Made

| File | Change |
|------|--------|
| `defaults/main.yml` | Add `fail2ban_start_service: true` |
| `tasks/main.yml` | Split into "Enable fail2ban" (always) + "Start fail2ban" (when: start_service) |
| `tasks/verify.yml` | Gate runtime checks on `fail2ban_start_service`; add `meta: flush_handlers` pattern; add diagnostic journalctl task |
| `molecule/docker/prepare.yml` | Install iptables-nft with `--ask=4` |
| `molecule/docker/molecule.yml` | Add `extra-vars: "fail2ban_start_service=false"`; remove noop banaction group_vars |
| `molecule/vagrant/molecule.yml` | Add `host_vars.arch-vm.fail2ban_sshd_backend: polling` |
| `molecule/vagrant/prepare.yml` | Create dummy `/var/log/auth.log` for Arch + iptables-nft install |
| `vars/archlinux.yml` | Add `python-systemd` to packages (kept for production journald backend) |

---

## Lessons Learned

1. **Follow existing patterns first**: The firewall role's `firewall_start_service=false` pattern existed before we started. Reading similar roles before starting would have saved several CI rounds.

2. **Enable ≠ Start**: On Arch Linux, `pacman install` does NOT auto-enable systemd services. On Ubuntu, `apt install` often does via post-install scripts. Roles that combine `enabled: true` + `state: started` in one task must split them if one is conditionally skipped.

3. **backend=auto hides crashes**: When `python-systemd` causes a crash, `backend=auto` detection itself crashes fail2ban. Setting an explicit backend (`polling`) bypasses the problematic import entirely.

4. **Pacman conflict resolution**: `--ask=4` (ALPM_QUESTION_CONFLICT_PKG) allows atomic package replacement in a single transaction, maintaining all transitive dependencies.

5. **Diagnostic first**: Adding `journalctl -u service` output to verify.yml before assertions catches crash reasons in the CI log without extra rounds.
