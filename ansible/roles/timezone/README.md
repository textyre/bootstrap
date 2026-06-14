# timezone

Sets the system timezone and ensures the `tzdata` database package is installed.

## What this role does

- [x] Asserts OS family is supported (ROLE-003 preflight)
- [x] Can be disabled per host with `timezone_enabled: false`
- [x] Loads OS-specific backend variables from `vars/<os_family>.yml`
- [x] Validates `timezone_name` is defined and non-empty
- [x] Installs the timezone database package when `timezone_manage_tzdata` is true
- [x] Sets system timezone via `community.general.timezone` (`/etc/localtime` symlink on all platforms; `/etc/timezone` only on non-systemd Debian/Ubuntu)
- [x] Verifies the applied timezone via `readlink -f /etc/localtime` and `timedatectl` on systemd (ROLE-005, `tasks/verify.yml`)
- [x] Restarts cron after an actual timezone change when cron is present
- [x] Reports execution phases via `common/report_phase.yml` (ROLE-008)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone_enabled` | `true` | Enable or disable the entire role |
| `timezone_name` | `"UTC"` | Timezone name in tz database format (`ls /usr/share/zoneinfo/`) |
| `timezone_manage_tzdata` | `true` | Install the OS-specific timezone database package from `vars/<os_family>.yml` |
| `timezone_restart_cron_enabled` | `true` | Restart cron after `community.general.timezone` reports a real change |

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

## Responsibility boundaries

| Concern | Owner |
|---------|-------|
| System timezone (`/etc/localtime`) | this role |
| tzdata package currency | this role |
| RTC hardware clock mode (UTC vs local) | `ntp` role (`ntp_rtcsync: true`) |
| Clock accuracy (NTP sync) | `ntp` role (chrony) |

## Cron restart

The role does not use Ansible handlers for cron. After setting the timezone it
registers the `community.general.timezone` result and includes
`tasks/restart_cron.yml` only when the timezone changed and
`timezone_restart_cron_enabled` is true.

`tasks/restart_cron.yml` collects `service_facts`, resolves the cron service
name from the current `ansible_facts['service_mgr']`, and restarts cron only
when the service exists. This avoids `meta: flush_handlers`, so this role does
not flush unrelated handlers from the surrounding play.

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

Converge and verify both load `inventory/group_vars/all/system.yml`, so Molecule
uses the same `timezone_name` variable path as the workstation play.

### Docker scenario — platform-differentiated testing

| Platform | Cron? | Tests |
|----------|-------|-------|
| Archlinux-systemd | installed | restart path, tzdata installed |
| Ubuntu-systemd | absent | restart skip path, tzdata installed |

### Negative tests

- Invalid timezone name (`Invalid/NotATimezone`) is rejected by `community.general.timezone`
- Timezone zone file validated against `/usr/share/zoneinfo/`

## Supported platforms

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo

## Tags

`timezone`, `report`

## License

MIT
