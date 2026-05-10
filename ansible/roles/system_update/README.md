# system_update

Performs a full operating-system package upgrade before workstation configuration.

## Contract

- `system_update` updates the installed OS only.
- It does not install the workstation package set.
- It does not install AUR packages.
- It does not configure services, users, desktop, Docker, VM integration, or dotfiles.
- On Arch Linux, it must leave `pacman` unlocked for the next workflow step.
- A reboot boundary is required after a successful run and before `task workstation`.

## Workflow

```bash
task prepare:system
reboot
task workstation
```

On Arch Linux the role also normalizes the `pacman` transaction boundary: if the
upgrade leaves a stale `/var/lib/pacman/db.lck` behind and no package-manager
processes are still running, the role removes the stale lock before handing
control to the reboot/workstation workflow.

`system_update` is now invoked by `ansible/playbooks/prepare_system.yml` after
the `bootloader` role. It is not exposed as a standalone public Taskfile entry.

## Backends

| OS family | Status | Backend |
|-----------|--------|---------|
| Archlinux | implemented | `pacman -Sy` → `archlinux-keyring` → `pacman -Su` → stale `db.lck` cleanup |
| Debian | blocked | fail-fast diagnostic |
| RedHat | blocked | fail-fast diagnostic |
| Void | blocked | fail-fast diagnostic |
| Gentoo | blocked | fail-fast diagnostic |

The non-Arch backends are explicit blockers in this slice. They must not silently skip.
