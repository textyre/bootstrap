# system_update

Performs a full operating-system package upgrade before workstation configuration.

## Contract

- `system_update` updates the installed OS only.
- It does not install the workstation package set.
- It does not install AUR packages.
- It does not configure services, users, desktop, Docker, VM integration, or dotfiles.
- It runs package transaction recovery as a generic post-upgrade phase.
- On Arch Linux, the recovery backend must leave `pacman` unlocked and the
  pacman database consistent for the next workflow step.
- A reboot boundary is required after a successful run and before `task workstation`.

## Workflow

```bash
task prepare:system
reboot
task workstation
```

After the OS-specific upgrade backend, the role runs a generic package
transaction recovery phase. The phase dispatches to an OS-family backend. On
Arch Linux that backend waits for any pacman lock holder to finish, removes only
an ownerless `/var/lib/pacman/db.lck`, checks `pacman -Dk`, and runs bounded
repair attempts before handing control to the reboot/workstation workflow.

`system_update` is now invoked by `ansible/playbooks/prepare_system.yml` after
the `bootloader` role. It is not exposed as a standalone public Taskfile entry.

## Backends

| OS family | Status | Backend |
|-----------|--------|---------|
| Archlinux | implemented | upgrade backend: `pacman -Sy` → `archlinux-keyring` → `pacman -Su`; recovery backend: pacman transaction recovery |
| Debian | blocked | fail-fast diagnostic |
| RedHat | blocked | fail-fast diagnostic |
| Void | blocked | fail-fast diagnostic |
| Gentoo | blocked | fail-fast diagnostic |

The non-Arch backends are explicit blockers in this slice. They must not silently skip.
