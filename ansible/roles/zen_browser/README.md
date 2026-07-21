# zen_browser

Makes Zen Browser the default web browser for the workstation user.

The role does not install the application. The `packages` stage must provide
Zen Browser and `xdg-utils`, and the `user` stage must provide `target_user`
before this role runs. The current Arch Linux workstation inventory installs
`zen-browser-bin` from the central `packages_aur` registry.

## Execution flow

1. **Configure** (`tasks/configure/main.yml`) - assigns `zen.desktop` as the XDG handler for HTML, HTTP, and HTTPS for `target_user`.
2. **Report** (`tasks/main.yml`) - records the configured user and desktop handler.

The role has no handlers, shell commands, temporary password files, or package
manager logic. `community.general.xdg_mime` reads the current associations and
changes only MIME types that do not already use Zen Browser.

## Variables

The role has no role-specific public variables. It uses the project-wide
`target_user`, which identifies the existing workstation account whose XDG
associations are configured. The `zen.desktop` ID and managed web MIME types
are internal constants in `vars/main.yml`, based on the installed desktop entry
rather than user-selectable role behavior.

## Examples

### Configure the workstation user

```yaml
# inventory/host_vars/workstation/zen_browser.yml
target_user: textyre
```

## Package boundary

The Arch package is declared once in
`inventory/group_vars/all/packages.yml`. It provides the `zen.desktop` desktop
entry consumed by this role. The role does not overwrite package-owned files.

## Cross-platform details

The XDG configuration works on Arch Linux, Ubuntu, Fedora, Void Linux, and
Gentoo when the external prerequisites above are available. The current
workstation package inventory provides Zen Browser only on Arch Linux.

## Logs

The role creates no logs. XDG associations are stored in the target user's
standard MIME application configuration, usually
`~/.config/mimeapps.list`.

## Troubleshooting

| Symptom | Diagnosis | Resolution |
|---------|-----------|------------|
| Zen Browser is not installed | Check the `packages` role output and `packages_aur` registry | Run the package stage before this role. |
| Association is unchanged | Confirm `/usr/share/applications/zen.desktop` exists | Install the supported Zen package, then rerun the role. |
| Wrong user's browser changed | Inspect `target_user` in inventory | Set the common target user correctly and rerun the role. |
| An application ignores the XDG default | Run `xdg-mime query default x-scheme-handler/https` as the user | Check whether that application uses a separate desktop-specific association API. |

## Testing

Docker and Vagrant scenarios provide `xdg-utils`, ACL support for unprivileged
execution, and a normal target user. Both run the same role on Arch Linux and
Ubuntu and require a zero-change idempotence pass. They do not repeat the
result check already performed by `community.general.xdg_mime`, and they do not
download the AUR application because package installation belongs to
`packages`, not this role.

All Ansible and Molecule operations run on the remote VM or in CI.
