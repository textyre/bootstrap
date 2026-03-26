# packages

> Role reference. For full README see `ansible/roles/packages/README.md`.

## Overview

Installs workstation packages via OS-native package managers (pacman, apt).
Supports Arch Linux and Debian/Ubuntu. No service management.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `packages_enabled` | `true` | Set `false` to skip the role on a host |
| `packages_base` | `[]` | Core CLI utilities |
| `packages_editors` | `[]` | Text editors and IDEs |
| `packages_docker` | `[]` | Docker and container tools |
| `packages_xorg` | `[]` | X.Org display server and drivers |
| `packages_wm` | `[]` | Window manager and compositor |
| `packages_filemanager` | `[]` | File manager tools |
| `packages_network` | `[]` | Networking utilities |
| `packages_media` | `[]` | Audio and video players |
| `packages_desktop` | `[]` | Desktop environment extras |
| `packages_graphics` | `[]` | Image viewers and graphics tools |
| `packages_session` | `[]` | Session management |
| `packages_terminal` | `[]` | Terminal emulators |
| `packages_fonts` | `[]` | Fonts |
| `packages_theming` | `[]` | GTK/Qt themes |
| `packages_search` | `[]` | Search utilities (fzf, ripgrep) |
| `packages_viewers` | `[]` | File viewers (bat, jq) |
| `packages_distro` | `{}` | Distro-specific extras keyed by `os_family` |

## Dependencies

None — `meta/main.yml` contains `dependencies: []`.

Uses `common` role tasks (`report_phase.yml`, `report_render.yml`) for execution reporting, skipped via `--skip-tags report`.

## Tags

| Tag | Description |
|-----|-------------|
| `packages` | Entire role |
| `packages,install` | Build package list + install step only |
| `packages,install,upgrade` | System upgrade + install (Arch only) |
| `report` | Execution report tasks only |

## Platform support

| OS | OS Family | Package manager | Notes |
|----|-----------|-----------------|-------|
| Arch Linux | Archlinux | pacman | Runs `pacman -Syu` before install |
| Ubuntu | Debian | apt | Runs `apt update` before install |
| Fedora | RedHat | — | Supported by preflight; no install task yet (stub) |
| Void Linux | Void | — | Supported by preflight; no install task yet (stub) |
| Gentoo | Gentoo | — | Supported by preflight; no install task yet (stub) |

## Testing

| Scenario | Driver | Coverage |
|----------|--------|---------|
| `docker` | Docker | Arch + Ubuntu (full list) + Arch + Ubuntu (empty list edge case) |
| `vagrant` | Vagrant/KVM | Arch VM + Ubuntu VM (full list) |

Run: `molecule test -s docker` or `molecule test -s vagrant` from `ansible/roles/packages/`.

## Verification

In-role verify (`tasks/verify.yml`) uses two techniques per package:

1. Native PM command — `pacman -Q <pkg>` (Arch) or `dpkg-query -W <pkg>` (Debian)
2. `package_facts` assert — confirms presence in Ansible fact database

Molecule verify (`molecule/shared/verify.yml`) mirrors these checks externally.
