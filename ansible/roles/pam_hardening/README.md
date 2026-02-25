# pam_hardening

PAM brute-force protection via `pam_faillock` with full parametrization across four platform families.

## What this role does

- [x] Deploys `/etc/security/faillock.conf` from Jinja2 template (cross-platform)
- [x] Activates `pam_faillock.so` in `/etc/pam.d/system-auth` (Arch, Void)
- [x] Installs and activates `pam-auth-update` profiles (Debian, Ubuntu)
- [x] Enables `with-faillock` feature via `authselect` (Fedora, RHEL)
- [x] Locks root account after failed attempts (`even_deny_root`)
- [x] Emits audit log entries for failed authentication (`audit`)
- [x] Skips X11 screensaver sessions to prevent false lockouts (`x11_skip`)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `pam_hardening_faillock_enabled` | `true` | Enable/disable the role entirely |
| `pam_hardening_faillock_deny` | `3` | Lock account after N failed attempts |
| `pam_hardening_faillock_fail_interval` | `900` | Counting window in seconds |
| `pam_hardening_faillock_unlock_time` | `900` | Lockout duration in seconds (0 = permanent) |
| `pam_hardening_faillock_root_unlock_time` | `900` | Root lockout duration (-1 = permanent) |
| `pam_hardening_faillock_audit` | `true` | Write failed attempts to audit log |
| `pam_hardening_faillock_silent` | `false` | Suppress lockout message to user |
| `pam_hardening_faillock_even_deny_root` | `true` | Apply lockout to root account |
| `pam_hardening_faillock_local_users_only` | `false` | Skip LDAP/SSO users (prevent false lockouts) |
| `pam_hardening_faillock_nodelay` | `false` | Remove post-failure delay (pam ≥ 1.5.1) |
| `pam_hardening_faillock_x11_skip` | `false` | Ignore X11 session auth attempts (screensaver) |

### x11_skip note

Set `pam_hardening_faillock_x11_skip: true` when `deny ≤ 3` and a GUI login manager (LightDM, SDDM) is in use. Without this, a locked screensaver can exhaust the failure counter before a real brute-force attempt begins.

### local_users_only note

Set `pam_hardening_faillock_local_users_only: true` in environments with LDAP/SSSD/SSO. Without it, a network blip causing LDAP timeouts will register as authentication failures and lock local accounts.

## Security baseline

Implements CIS Level 1 Workstation controls:

| CIS Control | Requirement | This role |
|-------------|-------------|-----------|
| 5.4.2 | Lock accounts after failed logins | `deny = 3` |
| 5.4.3 | Unlock time ≥ 900s | `unlock_time = 900` |
| 5.4.4 | Root subject to lockout | `even_deny_root` |

Follows guidance from: dev-sec Linux Baseline, Kicksecure hardening, VMware Photon OS STIGs.

## Platform support

| Platform | `os_family` | PAM method |
|----------|-------------|-----------|
| Arch Linux | `Archlinux` | `lineinfile` → `/etc/pam.d/system-auth` |
| Void Linux | `Void` | `lineinfile` → `/etc/pam.d/system-auth` |
| Debian / Ubuntu | `Debian` | `pam-auth-update --package` with two profile files |
| Fedora / RHEL | `RedHat` | `authselect enable-feature with-faillock` |

## Tags

`pam_hardening`

## Molecule scenarios

| Scenario | Description |
|----------|-------------|
| `default` | Localhost (developer's Arch workstation), idempotence check |
| `docker` | Arch Linux systemd container — file content assertions |
| `vagrant` | `generic/arch` + `bento/ubuntu-24.04` — dual-platform PAM stack validation |
