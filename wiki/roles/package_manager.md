# package_manager

## Overview

Configure system package manager (pacman, apt, dnf, xbps, portage).

## Variables

See `ansible/roles/package_manager/defaults/main.yml` for the full list with defaults.

### Key variables

| Variable | Description |
|----------|-------------|
| `package_manager_enabled` | Master toggle |
| `package_manager_pacman_parallel_downloads` | Pacman parallel downloads (Arch) |
| `package_manager_pacman_siglevel` | Signature verification level (Arch) — supply chain sensitive |
| `package_manager_pacman_multilib` | Enable 32-bit multilib repo (Arch) |
| `package_manager_paccache_enabled` | Enable paccache timer (Arch) |
| `package_manager_makepkg_enabled` | Enable makepkg drop-in (Arch) |
| `package_manager_dnf_keepcache` | Keep dnf cache (Fedora) |

## Dependencies

- `reflector` — Arch mirror configuration
- `yay` — AUR helper
- `common` — Structured logging

## Tags

`packages`, `package-manager`, `pacman`, `paccache`, `makepkg`, `apt`, `dnf`, `xbps`, `portage`, `report`

## Audit events

| Event | Indicator | Threshold |
|-------|-----------|-----------|
| SigLevel changed | pacman.conf `SigLevel` directive differs from expected | Any change — supply chain risk |
| Multilib enabled | `[multilib]` section present when policy says disabled | Policy violation if unintended |
| paccache timer disabled | `systemctl is-enabled paccache.timer` returns non-enabled | Cache growth unchecked |
| External cache mount missing | `package_manager_pacman_cache_root` path doesn't exist | Pacman will fail to update |

## Monitoring

- `/var/log/pacman.log` — Arch package operations
- `/var/log/apt/history.log` — Debian/Ubuntu package operations
- `/var/log/dnf.log` — Fedora package operations
- `systemctl status paccache.timer` — Arch cache cleanup status

## Drift detection

The in-role `verify.yml` checks deployed configs match expected values on every run. If configs are manually edited, the role will detect the drift and re-deploy the template.
