# packages

Installs workstation packages via OS-native package managers (pacman, apt).

## What this role does

- [x] Performs a full system upgrade on Arch Linux (`pacman -Syu`) before installing packages
- [x] Builds a combined package list by aggregating 16 category lists into `packages_all`
- [x] Dispatches to OS-specific task files (`install-archlinux.yml`, `install-debian.yml`)
- [x] Installs packages via `community.general.pacman` (Arch) or `ansible.builtin.apt` (Debian/Ubuntu)
- [x] Reports the total number of installed packages

## Variables

All category lists default to `[]`. Override them in `group_vars/all/packages.yml`.

| Variable | Default | Description |
|----------|---------|-------------|
| `packages_base` | `[]` | Core CLI utilities (git, curl, htop, etc.) |
| `packages_editors` | `[]` | Text editors and IDEs |
| `packages_docker` | `[]` | Docker and container tools |
| `packages_xorg` | `[]` | X.Org display server and drivers |
| `packages_wm` | `[]` | Window manager and compositor |
| `packages_filemanager` | `[]` | File manager tools |
| `packages_network` | `[]` | Networking utilities |
| `packages_media` | `[]` | Audio and video players |
| `packages_desktop` | `[]` | Desktop environment extras |
| `packages_graphics` | `[]` | Image viewers and graphics tools |
| `packages_session` | `[]` | Session management and display managers |
| `packages_terminal` | `[]` | Terminal emulators |
| `packages_fonts` | `[]` | Fonts including Nerd Fonts |
| `packages_theming` | `[]` | GTK/Qt themes and icon packs |
| `packages_search` | `[]` | Search utilities (fzf, ripgrep) |
| `packages_viewers` | `[]` | File viewers (bat, jq) |
| `packages_distro` | `{}` | Distro-specific packages keyed by `os_family` (e.g. `Archlinux`, `Debian`) |

### Example

```yaml
# group_vars/all/packages.yml
packages_base:
  - git
  - curl
  - htop
  - tmux

packages_editors:
  - vim
  - neovim

packages_search:
  - fzf
  - ripgrep

packages_distro:
  Archlinux:
    - base-devel
    - pacman-contrib
  Debian:
    - build-essential
```

## Supported platforms

| OS | Package manager |
|----|----------------|
| Arch Linux | pacman (community.general.pacman) |
| Debian / Ubuntu | apt (ansible.builtin.apt) |

## Tags

| Tag | Effect |
|-----|--------|
| `install` | All tasks (default) |
| `upgrade` | System upgrade step only (Arch: `pacman -Syu`) |

Use `--skip-tags upgrade` to skip the system upgrade and only install/verify packages.

## Molecule tests

| Scenario | Driver | Platforms | Purpose |
|----------|--------|-----------|---------|
| `default` | localhost (delegated) | Current host | Quick local dev check |
| `docker` | Docker | Arch Linux (systemd container) | CI container test |
| `vagrant` | Vagrant (libvirt) | Arch Linux + Ubuntu 24.04 | Full cross-platform test |

All scenarios share `molecule/shared/converge.yml` and `molecule/shared/verify.yml`.

### Running tests

```bash
# Quick local check (installs packages on localhost!)
molecule test -s default

# Docker (Arch container)
molecule test -s docker

# Full cross-platform (Arch VM + Ubuntu VM)
molecule test -s vagrant
```

### Verify approach

Verification uses `ansible.builtin.package_facts` (cross-platform) rather than raw shell commands. Each expected package is asserted to exist in `ansible_facts.packages`, followed by a check-mode idempotence assertion.
