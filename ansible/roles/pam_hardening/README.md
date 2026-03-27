# pam_hardening

Protects user accounts from brute-force attacks via `pam_faillock` lockout policy.

## Execution flow

1. **Preflight assert** (`tasks/main.yml`) — checks `os_family` is in the supported list; fails immediately on unsupported OS
2. **Deploy faillock.conf** (`tasks/faillock.yml`) — renders `/etc/security/faillock.conf` from Jinja2 template with all configured parameters (deny, unlock_time, root_unlock_time, audit, silent, etc.)
3. **Activate PAM stack** (platform-specific dispatch via `faillock_<os_family>.yml`):
   - *Arch/Void/Gentoo* — inserts `pam_faillock.so` lines into `/etc/pam.d/system-auth` (preauth, authfail, account)
   - *Debian/Ubuntu* — deploys two `pam-auth-update` profile files, **triggers handler:** `pam-auth-update --package` reconfigures the PAM stack
   - *Fedora/RHEL* — runs `authselect enable-feature with-faillock`, **triggers handler:** `authselect apply-changes`
4. **Verify** (`tasks/verify.yml`) — slurps `faillock.conf` and asserts deny value matches; checks platform-specific PAM stack (system-auth / common-auth / authselect) to confirm faillock is active
5. **Report** — writes execution report via `common/report_phase.yml` + `report_render.yml`

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `Update PAM (Debian)` | Profile file change (step 3) | Runs `pam-auth-update --package` to reconfigure PAM stack. **Warning:** affects all PAM profiles, not just faillock — see [Troubleshooting](#troubleshooting) |
| `Apply authselect (RedHat)` | authselect feature change (step 3) | Runs `authselect apply-changes` to regenerate PAM symlinks |

## Variables

### Configurable (`defaults/main.yml`)

Override via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `pam_hardening_faillock_enabled` | `true` | safe | Set `false` to skip the role entirely |
| `pam_hardening_faillock_deny` | `3` | careful | Lock account after N failed attempts. `1` = lockout after single typo |
| `pam_hardening_faillock_fail_interval` | `900` | safe | Counting window in seconds (15 min) |
| `pam_hardening_faillock_unlock_time` | `900` | careful | Lockout duration in seconds. `0` = permanent lockout (manual unlock required) |
| `pam_hardening_faillock_root_unlock_time` | `900` | careful | Root lockout duration. `-1` = permanent (requires another admin account to unlock) |
| `pam_hardening_faillock_audit` | `true` | safe | Write failed attempts to audit log |
| `pam_hardening_faillock_silent` | `false` | safe | Suppress lockout message shown to user |
| `pam_hardening_faillock_even_deny_root` | `true` | careful | Apply lockout to root account. If root gets locked and `root_unlock_time=-1`, only another admin can unlock |
| `pam_hardening_faillock_local_users_only` | `false` | safe | Skip LDAP/SSO users. Set `true` with LDAP/SSSD to prevent false lockouts from network blips |
| `pam_hardening_faillock_nodelay` | `false` | safe | Remove post-failure delay (requires pam >= 1.5.1) |

## Examples

### LDAP/SSO environment

```yaml
# In group_vars/all/pam.yml:
pam_hardening_faillock_local_users_only: true
```

Prevents network timeouts from registering as authentication failures and locking local accounts.

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/pam.yml:
pam_hardening_faillock_enabled: false
```

## Security baseline

Implements CIS Level 1 Workstation controls:

| CIS Control | Requirement | This role |
|-------------|-------------|-----------|
| 5.4.2 | Lock accounts after failed logins | `deny = 3` |
| 5.4.3 | Unlock time >= 900s | `unlock_time = 900` |
| 5.4.4 | Root subject to lockout | `even_deny_root` |

Follows guidance from: dev-sec Linux Baseline, Kicksecure hardening, VMware Photon OS STIGs.

## Cross-platform details

| Aspect | Arch / Void / Gentoo | Debian / Ubuntu | Fedora / RHEL |
|--------|---------------------|-----------------|---------------|
| PAM method | `lineinfile` on system-auth | `pam-auth-update --package` | `authselect enable-feature` |
| PAM config file | `/etc/pam.d/system-auth` | `/etc/pam.d/common-auth` | managed by authselect |
| Activation check | `grep pam_faillock /etc/pam.d/system-auth` | `grep pam_faillock /etc/pam.d/common-auth` | `authselect current` |

All platforms share `/etc/security/faillock.conf` for faillock parameters.

## Logs

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| Faillock tally | `/run/faillock/<username>` | Binary tally of failed attempts per user | tmpfs — cleared on reboot |
| Audit log | `/var/log/audit/audit.log` or `journalctl` | `pam_faillock` events when `audit=true` | System journal/auditd rotation |

### Reading the logs

- View failed attempts: `faillock --user <username>`
- Reset a user's lockout: `faillock --user <username> --reset`
- Check audit events: `ausearch -m USER_AUTH -ts recent` or `journalctl _COMM=login -n 50`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Account locked after few attempts | `faillock --user <name>` — check tally count | `faillock --user <name> --reset` to unlock. Consider increasing `deny` |
| Root account permanently locked | `even_deny_root=true` + `root_unlock_time=-1` | Boot into single-user/rescue mode, run `faillock --user root --reset` |
| Screensaver locks account | X11 auth attempts counted against deny limit | Separate PAM service config for screensaver without pam_faillock |
| LDAP users getting locked | Network timeouts counted as failures | Set `pam_hardening_faillock_local_users_only: true` |
| `pam-auth-update --package` breaks other PAM modules | Handler reconfigures entire PAM stack, may affect LDAP/MFA modules | Check `/etc/pam.d/common-auth` after role run. Restore from backup if needed |
| Role reports `ok` but faillock not active | PAM stack not configured (profile conflict on Debian, authselect issue on Fedora) | Run verify: `grep pam_faillock /etc/pam.d/system-auth` (Arch) or `authselect current` (Fedora) |
| `authselect enable-feature` fails | No authselect profile selected on Fedora | Run `authselect select sssd --force` first, then re-run the role |

## Testing

Both scenarios are required. Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Arch + Ubuntu + Fedora: config deploy, PAM stack, idempotence |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic or PAM handlers | Real systemd, real packages, Arch + Ubuntu VMs |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Config files | `/etc/security/faillock.conf` exists, root:root 0644, correct content | TEST-008 |
| Boolean directives | silent, nodelay, local_users_only present/absent per defaults | TEST-008 |
| PAM stack (Arch) | `pam_faillock.so` preauth + authfail + account in system-auth | TEST-008 |
| PAM stack (Debian) | Profile files deployed, `pam_faillock.so` in common-auth | TEST-008 |
| PAM stack (Fedora) | `authselect current` shows `with-faillock` | TEST-008 |
| Permissions | faillock.conf mode 0644 owned by root | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `authselect` not found (Fedora) | Minimal Fedora container missing authselect | Check `prepare.yml` installs `authselect` package |
| Idempotence failure on lineinfile | Duplicate `pam_faillock.so` lines in system-auth | Check system-auth doesn't already contain faillock lines from base image |
| `pam-auth-update` not applied | Handler didn't fire (no change detected) | Run `molecule converge` then check `/etc/pam.d/common-auth` manually |
| Assertion failed with no details | Missing `fail_msg` in verify.yml assert | Add `fail_msg` with expected + actual values |
| Preflight assert fails | Running on unsupported OS family | Check `_pam_hardening_supported_os` in defaults |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `pam_hardening` | Entire role | Full apply: `ansible-playbook playbook.yml --tags pam_hardening` |
| `pam`, `security`, `faillock` | Faillock configuration tasks | Targeted faillock apply |
| `cis_5.4.2` | CIS-tagged tasks only | Compliance audit: `--tags cis_5.4.2` |
| `report` | Execution report only | Re-generate report: `--tags report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings + supported OS list | No — override via inventory |
| `templates/faillock.conf.j2` | faillock.conf Jinja2 template | When changing config file format |
| `tasks/main.yml` | Execution flow orchestrator (preflight, configure, verify, report) | When adding/removing steps |
| `tasks/faillock.yml` | Config deploy + OS dispatch | When changing dispatch logic |
| `tasks/faillock_archlinux.yml` | PAM stack setup for Arch/Void/Gentoo (lineinfile) | When changing lineinfile patterns |
| `tasks/faillock_debian.yml` | PAM stack setup for Debian/Ubuntu (pam-auth-update) | When changing profile format |
| `tasks/faillock_redhat.yml` | PAM stack setup for Fedora/RHEL (authselect) | When changing authselect usage |
| `tasks/verify.yml` | In-role post-deploy verification | When adding verification checks |
| `handlers/main.yml` | PAM update handlers (Debian + RedHat) | Rarely |
| `meta/main.yml` | Galaxy metadata and platform list | When adding platform support |
| `molecule/` | Test scenarios (docker, vagrant, default) | When changing test coverage |
