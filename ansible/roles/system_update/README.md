# system_update

Performs a full operating-system package upgrade before workstation configuration.

## Contract

- `system_update` updates the installed OS only.
- It does not install the workstation package set.
- It does not install AUR packages.
- It does not configure services, users, desktop, Docker, VM integration, or dotfiles.
- A reboot boundary is required after a successful run and before `task workstation`.

## Workflow

```bash
task system:update
reboot
task workstation
```

## Backends

| OS family | Status | Backend |
|-----------|--------|---------|
| Archlinux | implemented | `pacman -Sy` → `archlinux-keyring` → `pacman -Su` |
| Debian | blocked | fail-fast diagnostic |
| RedHat | blocked | fail-fast diagnostic |
| Void | blocked | fail-fast diagnostic |
| Gentoo | blocked | fail-fast diagnostic |

The non-Arch backends are explicit blockers in this slice. They must not silently skip.
