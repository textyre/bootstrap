# timezone

Sets the system timezone and ensures the `tzdata` database package is installed.

## What this role does

- [x] Asserts OS family is supported (ROLE-003 preflight)
- [x] Validates `timezone_name` is defined and non-empty
- [x] Installs `tzdata` package (name resolved from `timezone_packages_tzdata` dict, keyed by `os_family`; skipped when undefined)
- [x] Sets system timezone via `community.general.timezone` (`/etc/localtime` symlink on all platforms; `/etc/timezone` only on non-systemd Debian/Ubuntu)
- [x] Verifies the applied timezone via `readlink -f /etc/localtime` and `timedatectl` on systemd (ROLE-005, `tasks/verify.yml`)
- [x] Restarts cron after a timezone change (skipped when cron is not installed)
- [x] Reports execution phases via `common/report_phase.yml` (ROLE-008)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone_name` | `"UTC"` | Timezone name in tz database format (`ls /usr/share/zoneinfo/`) |
| `timezone_packages_tzdata` | _(undefined)_ | Package name dict keyed by `os_family` with `default` fallback. Task is skipped when undefined. |

Production values are set in `inventory/group_vars/all/system.yml`:

```yaml
timezone_name: "Asia/Almaty"
```

`timezone_packages_tzdata` comes from `inventory/group_vars/all/packages.yml`:

```yaml
timezone_packages_tzdata:
  Gentoo: "sys-libs/timezone-data"
  default: "tzdata"
```

## Responsibility boundaries

| Concern | Owner |
|---------|-------|
| System timezone (`/etc/localtime`) | this role |
| tzdata package currency | this role |
| RTC hardware clock mode (UTC vs local) | `ntp` role (`ntp_rtcsync: true`) |
| Clock accuracy (NTP sync) | `ntp` role (chrony) |

## Handlers

`restart cron` — triggered by timezone change. Collects `service_facts` and restarts the distro-appropriate cron daemon only when present.
Checks both bare (`crond`) and systemd (`crond.service`) service keys.

| OS family | Cron service |
|-----------|-------------|
| Archlinux | `crond` |
| Debian / Ubuntu | `cron` |
| RedHat | `crond` |
| Void / Gentoo | `crond` |

## Testing

```bash
# Localhost (Arch only, fast, no Docker)
molecule test -s default

# Docker (Arch + Ubuntu systemd containers, idempotence check)
molecule test -s docker

# Vagrant (Arch + Ubuntu full VMs, cross-platform)
molecule test -s vagrant
```

All three scenarios share `molecule/shared/converge.yml` and `molecule/shared/verify.yml`.
Vagrant requires `libvirt` provider.

Docker prepare imports shared `molecule/shared/prepare-docker.yml` for cache updates,
then adds role-specific cron installation for Archlinux only.

### Docker scenario — platform-differentiated testing

| Platform | Cron? | `timezone_packages_tzdata`? | Tests |
|----------|-------|----------------------------|-------|
| Archlinux-systemd | installed | defined (host_vars) | handler fires, tzdata installed |
| Ubuntu-systemd | absent | undefined | handler skips, tzdata install skipped |

### Negative tests

- Invalid timezone name (`Invalid/NotATimezone`) is rejected by `community.general.timezone`
- Timezone zone file validated against `/usr/share/zoneinfo/`

## Supported platforms

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo

## Tags

`timezone`, `timezone,report`

## License

MIT
