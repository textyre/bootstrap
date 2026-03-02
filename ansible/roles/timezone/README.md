# timezone

Sets the system timezone and ensures the `tzdata` database package is installed.

## What this role does

- [x] Installs `tzdata` package (name resolved from `timezone_packages_tzdata` dict, keyed by `os_family`)
- [x] Sets system timezone via `community.general.timezone` (`/etc/localtime` symlink on all platforms; `/etc/timezone` only on non-systemd Debian/Ubuntu)
- [x] Verifies the applied timezone via `readlink -f /etc/localtime`
- [x] Restarts cron after a timezone change (skipped when cron is not installed)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone_name` | `"UTC"` | Timezone name in tz database format (`timedatectl list-timezones`) |
| `timezone_packages_tzdata` | _(undefined)_ | Package name dict keyed by `os_family` with `default` fallback. Task is skipped when undefined. |

Production values are set in `group_vars/all/system.yml`:

```yaml
timezone_name: "Asia/Almaty"
```

`timezone_packages_tzdata` comes from `group_vars/all/packages.yml`:

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

Vagrant requires `libvirt` provider. All three scenarios share `molecule/shared/converge.yml` and `molecule/shared/verify.yml`.
Scenario test vars are defined in each `molecule.yml` under `provisioner.inventory.group_vars.all`.

## Supported platforms

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo

## Tags

`timezone`, `timezone,report`

## License

MIT
