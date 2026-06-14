# timezone

Sets the system timezone and ensures the `tzdata` database package is installed.

## What this role does

- [x] Asserts OS family is supported (ROLE-003 preflight)
- [x] Can be disabled per host with `timezone_enabled: false`
- [x] Loads OS-specific backend variables from `vars/<os_family>/main.yml`
- [x] Validates `timezone_name` is defined and non-empty
- [x] Installs the timezone database package
- [x] Sets system timezone via `community.general.timezone` (`/etc/localtime` symlink on all platforms; `/etc/timezone` only on non-systemd Debian/Ubuntu)
- [x] Verifies the applied timezone via common checks and init-specific verify tasks (ROLE-005, `tasks/verify.yml`)
- [x] Restarts cron after an actual timezone change
- [x] Reports execution phases via `common/report_phase.yml` (ROLE-008)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone_enabled` | `true` | Enable or disable the entire role |
| `timezone_name` | required | Timezone name in tz database format (`ls /usr/share/zoneinfo/`) |

Production timezone values are set in `inventory/group_vars/all/system.yml`:

```yaml
timezone_name: "Asia/Almaty"
```

Role-internal OS backend variables:

| OS family | Timezone package | Cron service default |
|-----------|------------------|----------------------|
| Archlinux | `tzdata` | `cronie` |
| Debian | `tzdata` | `cron` |
| RedHat | `tzdata` | `crond` |
| Void | `tzdata` | `cronie` |
| Gentoo | `sys-libs/timezone-data` | `cronie` |

## Task flow

`tasks/main.yml` is a router:

- `assert.yml` — supported OS, OS-specific vars, `timezone_name`
- `install.yml` — timezone database package
- `set_timezone.yml` — `community.general.timezone`
- `restart_cron.yml` — cron restart after a timezone change
- `verify.yml` — in-role verification dispatcher
- `verify/localtime.yml` — `/etc/localtime` target check
- `verify/tzdata.yml` — timezone database package check dispatcher
- `verify/tzdata/<os_family>/main.yml` — OS-specific timezone database package assertion
- `verify/systemd/main.yml` — systemd-specific `timedatectl` check
- `report.yml` — execution report rendering

## Responsibility boundaries

| Concern | Owner |
|---------|-------|
| System timezone (`/etc/localtime`) | this role |
| tzdata package currency | this role |
| RTC hardware clock mode (UTC vs local) | `ntp` role (`ntp_rtcsync: true`) |
| Clock accuracy (NTP sync) | `ntp` role (chrony) |

## Cron restart

The role does not use Ansible handlers for cron. After setting the timezone it
includes `tasks/restart_cron.yml` when `community.general.timezone` reports a
real change.

`tasks/restart_cron.yml` resolves the cron service name once from the current
`ansible_facts['service_mgr']`, restarts it when the timezone changed, and
asserts that the restart task reported `changed`. It does not gather service
facts or publish role-local bookkeeping via `set_fact`. This avoids
`meta: flush_handlers`, so this role does not flush unrelated handlers from the
surrounding play.

## Testing

```bash
# Localhost (Arch only, fast, no Docker)
molecule test -s default

# Docker (Arch + Ubuntu systemd containers, idempotence check)
molecule test -s docker

# Vagrant (Arch + Ubuntu full VMs, cross-platform)
molecule test -s vagrant
```

All three scenarios share `molecule/shared/converge.yml`.
Vagrant requires `libvirt` provider.

Docker prepare imports shared `molecule/shared/prepare-docker.yml` for cache updates,
then adds role-specific cron installation for the tested platforms.

Molecule sets `timezone_name: "Asia/Almaty"` directly and does not depend on
workstation inventory group vars.

Molecule does not run a separate verify playbook for this role. The role performs
its runtime checks during converge, so the scenarios test that converge succeeds,
idempotence holds, and the same role flow works across the platform matrix.

### Docker scenario — platform-differentiated testing

| Platform | Cron? | Tests |
|----------|-------|-------|
| Archlinux-systemd | installed | restart path, tzdata installed |
| Ubuntu-systemd | installed | restart path, tzdata installed |

## Supported platforms

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo

## Tags

`timezone`, `report`

## License

MIT
