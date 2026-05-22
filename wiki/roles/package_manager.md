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

- `yay` — AUR helper; part of the Arch package manager contract alongside pacman
- `common` — Structured logging

These are local bootstrap roles resolved through `ANSIBLE_ROLES_PATH`, not
Galaxy roles resolved through a role-local `requirements.yml`.

## Ownership contract

The role owns the full Arch `/etc/pacman.conf` and Fedora `/etc/dnf/dnf.conf`
files. Manual edits to those files are expected to be overwritten. Debian/Ubuntu
and Void use role-owned drop-ins under `/etc/apt/apt.conf.d/` and `/etc/xbps.d/`.

## Architecture

- `tasks/main.yml` is only the role flow: validate, OS dispatch, verify, report.
- `tasks/validate.yml` is only the preflight dispatcher and supported OS assert.
- OS-specific task directories match `ansible_facts['os_family']`: `archlinux/`, `debian/`, `redhat/`, `void/`, `gentoo/`.
- Each OS directory owns its own `main.yml`, `validate.yml`, and `verify.yml`.
- `tasks/archlinux/paccache.yml` is the paccache dispatcher and support assert; systemd implementation lives in `tasks/archlinux/systemd/paccache.yml`.
- `tasks/archlinux/yay.yml` imports the `yay` role in setup-only mode because Arch package management is `pacman` plus `yay` in this project.
- `tasks/verify.yml` dispatches to OS-specific verify files. Verification checks ownership markers and read-only package-manager parser probes.
- The role does not set computed host facts; intermediate values stay in registered task results or task-local vars.
- Molecule shared converge and verify playbooks follow the same dispatcher pattern, with real OS-specific files only where checks exist.

## Tags

`package_manager`

The role intentionally exposes one tag. It decides internally which OS-specific
package manager work applies to the host.

## Ordering assumptions

`reflector` remains a separate role. Playbooks that depend on refreshed Arch
mirrors should run `reflector` before `package_manager`; `package_manager` does
not orchestrate reflector itself.

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

The in-role verify dispatcher checks deployed configs match expected values on
every run and confirms package managers can parse/read their configuration. If
configs are manually edited, the role will re-deploy managed templates.
