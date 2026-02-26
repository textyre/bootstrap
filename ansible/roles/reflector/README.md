# reflector

Pacman mirror list optimization via [reflector](https://wiki.archlinux.org/title/Reflector) with systemd timer automation and pacman hook integration.

**Arch Linux only.** The role hard-asserts `os_family == Archlinux` and uses Arch-specific paths (pacman mirrorlist, pacman hooks).

## What this role does

- [x] Installs `reflector` via pacman
- [x] Deploys `/etc/xdg/reflector/reflector.conf` from Jinja2 template (single source of truth for CLI flags)
- [x] Creates a systemd timer drop-in (`/etc/systemd/system/reflector.timer.d/override.conf`) with configurable schedule and randomized delay
- [x] Optionally deploys a pacman alpm hook (`/etc/pacman.d/hooks/reflector-mirrorlist.hook`) that re-runs reflector when `pacman-mirrorlist` is upgraded
- [x] Enables and starts `reflector.timer` (`daemon_reload: true`)
- [x] Backs up current mirrorlist before update (timestamped, with rotation)
- [x] Runs `reflector` with configurable retries and validates the output contains `Server =` entries
- [x] Restores backup on failure (rescue block)
- [x] Refreshes pacman cache after mirrorlist update

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `reflector_countries` | `"KZ,RU,DE,NL,FR"` | Comma-separated country codes for mirror selection |
| `reflector_protocol` | `"https"` | Mirror protocol |
| `reflector_latest` | `20` | Number of mirrors to keep |
| `reflector_sort` | `"rate"` | Sort method (`rate`, `age`, `score`, `country`) |
| `reflector_age` | `12` | Maximum mirror age in hours |
| `reflector_timer_schedule` | `"daily"` | Systemd `OnCalendar` value |
| `reflector_threads` | `4` | Parallel download threads |
| `reflector_conf_path` | `/etc/xdg/reflector/reflector.conf` | Config file path |
| `reflector_mirrorlist_path` | `/etc/pacman.d/mirrorlist` | Output mirrorlist path |
| `reflector_backup_mirrorlist` | `true` | Create timestamped backup before update |
| `reflector_retries` | `3` | Retry count for reflector command |
| `reflector_retry_delay` | `5` | Seconds between retries |
| `reflector_connection_timeout` | `10` | Connection timeout in seconds |
| `reflector_download_timeout` | `30` | Download timeout in seconds |
| `reflector_proxy` | `""` | HTTP/HTTPS proxy (empty = no proxy) |
| `reflector_backup_keep` | `3` | Max backup files to retain (`0` = unlimited) |
| `reflector_timer_randomized_delay` | `"1h"` | `RandomizedDelaySec` for timer |
| `reflector_pacman_hook` | `true` | Deploy pacman hook for auto-update on mirror package upgrade |

## Supported platforms

Arch Linux only.

## Tags

| Tag | Effect |
|-----|--------|
| `update` | All tasks in `update.yml` (backup, run reflector, validate, rotate, report) |

Use `--skip-tags update` to apply install/configure/service only (no network required, idempotent).

## Testing

Three molecule scenarios:

| Scenario | Driver | Network | Idempotence | Purpose |
|----------|--------|---------|-------------|---------|
| `default` | delegated (localhost) | full | no | Quick manual test on developer's Arch VM |
| `docker` | Docker | cache only | yes | Offline config/service test (`skip-tags: update`) |
| `vagrant` | Vagrant/libvirt | full | no | End-to-end test including `reflector` execution |

```bash
# Quick syntax check
molecule syntax -s default

# Offline test in Docker (requires arch-systemd image)
molecule test -s docker

# Full end-to-end test (requires libvirt + Vagrant)
molecule test -s vagrant
```

The docker scenario skips `update.yml` tasks (no internet needed for package/config/timer testing) and includes idempotence validation. The vagrant scenario runs the full role including mirror fetching, mirrorlist validation, and backup rotation.
