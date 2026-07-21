# lightdm

Configures and starts the LightDM display manager.

The role owns the LightDM configuration required to launch Xorg and the
LightDM service state. It does not install packages, configure the monitor,
or select and deploy a greeter. Those contracts belong to `packages`, `xorg`,
and `greeter`.

## Execution flow

1. **Validate** (`tasks/validate.yml`) - requires systemd before the role changes the host.
2. **Configure** (`tasks/configure/main.yml`) - deploys `/etc/lightdm/lightdm.conf.d/10-config.conf`.
3. **Service** (`tasks/service/main.yml`) - enables and starts `lightdm` through systemd.
4. **Report** (`tasks/main.yml`) - reports the managed file count and service state.

The role has no handlers. Repeated runs preserve the same configuration and
service state.

## Prerequisites

Before this role runs:

- the `lightdm` and Xorg packages must be installed;
- the `xorg` role must have provided the required Xorg configuration;
- a greeter must be installed and selected by its own LightDM configuration.

The ctOS greeter artifact provides
`/etc/lightdm/lightdm.conf.d/20-ctos-greeter.conf`, which selects
`nody-greeter`. LightDM reads that file together with the configuration owned
by this role.

## Variables

The role has no role-specific configurable variables.

It consumes the project-wide `dotfiles_base_dir`, which points to the dotfiles
checkout already present on the managed host.

## Managed configuration

`/etc/lightdm/lightdm.conf.d/10-config.conf` contains:

```ini
[Seat:*]
xserver-command=X -br
```

`xserver-command=X -br` tells LightDM to start Xorg without its default gray
root-window pattern. It does not choose a resolution. Xorg selects the mode
reported by the physical or virtual display unless the `xorg` role provides an
explicit monitor mode.

The role does not deploy or invoke `add-and-set-resolution.sh`.

## Platform support

The same LightDM configuration path is used on Arch Linux, Ubuntu, Fedora,
Void Linux, and Gentoo, so there is no distribution-specific task split.

Service management is currently implemented only for systemd. On runit,
OpenRC, s6, or dinit the validation phase fails before configuration is
changed, with a message that the init-specific implementation is missing.

## Troubleshooting

| Symptom | Check | Owner |
|---------|-------|-------|
| LightDM does not start | `journalctl -b -u lightdm` and the Xorg log | Install/runtime prerequisite or LightDM configuration |
| LightDM reports an unknown greeter | Installed greeter and its own file under `/etc/lightdm/lightdm.conf.d/` | `greeter` and `packages` |
| Login screen uses the wrong resolution | Xorg log and `/etc/X11/xorg.conf.d/10-monitor.conf` | `xorg` |
| Role rejects the init system | `ansible_facts['service_mgr']` | Missing init-specific LightDM service implementation |

## Testing

| Scenario | Coverage |
|----------|----------|
| `docker` | Arch Linux and Ubuntu configuration convergence and idempotence. A container has no graphical display, so this scenario intentionally runs only the configure phase. |
| `vagrant` | Arch Linux and Ubuntu full-role convergence and idempotence with LightDM, Xorg, and the distribution GTK greeter installed as package prerequisites. |

Molecule has no duplicate verify phase for file ownership or service state
already enforced by Ansible modules.

All Ansible and Molecule operations run on the remote VM or in CI.
