# xorg

Configures the system-wide X11 keyboard layout and monitor profile.

The role does not install Xorg or GPU drivers, start a display manager, or
manage graphical sessions. Those responsibilities belong to the package,
`gpu_drivers`, and `lightdm` roles.

## Execution flow

1. **Configure** (`tasks/configure/main.yml`) - creates the destination directory, copies the keyboard configuration, and renders the monitor policy into `/etc/X11/xorg.conf.d/`.
2. **Report** (`tasks/main.yml`) - records the number of managed files and renders the role report.

The role has no handlers and manages no service. Xorg reads these files when a
new X11 server starts.

## Variables

The role consumes the project-wide `dotfiles_base_dir` path provided by the
common inventory and exposes these monitor settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `xorg_monitor_mode` | `auto` | Uses the mode reported by the physical or virtual display. Set a mode such as `2560x1440` to select it explicitly. |
| `xorg_monitor_driver` | `modesetting` | Xorg video driver used only for an explicit monitor mode. |
| `xorg_monitor_modeline` | `""` | Optional timing values for a mode that the display does not advertise. |

### Internal (`vars/main.yml`)

`_xorg_system_files` defines the keyboard file copied from dotfiles. The monitor
file is rendered by the role template. There are no
distro-specific mappings because all supported systems use the same Xorg
configuration path and format.

## Examples

### Use a repository checkout on the managed host

```yaml
# inventory/host_vars/workstation/xorg.yml
dotfiles_base_dir: /home/textyre/bootstrap/dotfiles
```

The role reads its keyboard source file relative to the project-wide
`dotfiles_base_dir`. A missing source file makes the role fail without changing
the destination file.

### Use a fixed advertised mode

```yaml
xorg_monitor_mode: "2560x1440"
```

### Use a custom mode with explicit timings

```yaml
xorg_monitor_mode: "2560x1440_60.00"
xorg_monitor_driver: modesetting
xorg_monitor_modeline: "312.25 2560 2752 3024 3488 1440 1443 1448 1493 -hsync +vsync"
```

## Cross-platform details

Arch Linux, Ubuntu, Fedora, Void Linux, and Gentoo all receive the same files
under `/etc/X11/xorg.conf.d/`. The role contains no package, service, or init
system mapping because none is needed for this contract.

## Managed configuration

| File | Result for the user |
|------|---------------------|
| `00-keyboard.conf` | Makes US and Russian layouts available in X11 and switches them with Ctrl+Space. |
| `10-monitor.conf` | Uses automatic display mode selection by default or selects the explicitly configured mode. |

These settings affect X11 sessions only. Wayland compositors do not consume
Xorg monitor configuration.

## Logs

The role creates no logs. Xorg reports parsing, device, and mode errors in the
display manager journal and in the Xorg session log, whose location depends on
how Xorg was started.

```bash
journalctl -b | grep -Ei 'xorg|lightdm'
grep -E '\(EE\)|\(WW\)' ~/.local/share/xorg/Xorg.0.log
```

## Troubleshooting

| Symptom | Diagnosis | Resolution |
|---------|-----------|------------|
| Role cannot copy a source file | Check the reported path beneath `dotfiles_base_dir` | Sync dotfiles to the managed host or correct `dotfiles_base_dir`. |
| X11 starts with the wrong keyboard layout | Inspect `/etc/X11/xorg.conf.d/00-keyboard.conf` | Correct the source file and rerun the role. |
| X11 starts with the wrong resolution or a black screen | Inspect the Xorg log for `(EE)` and rejected modes | Return `xorg_monitor_mode` to `auto` or correct the explicit mode, driver, and optional modeline. |
| Wayland ignores the monitor file | Confirm the session type with `echo "$XDG_SESSION_TYPE"` | Configure the active Wayland compositor; this role intentionally configures X11 only. |

## Testing

| Scenario | Coverage |
|----------|----------|
| `docker` | Clean Arch Linux container with automatic mode and Ubuntu container with a fixed mode; convergence and idempotence. |
| `vagrant` | Arch Linux VM with automatic mode and Ubuntu VM with a fixed mode; real filesystem convergence and idempotence. |

Docker is a configuration-only scenario: it does not start a graphical server.
Vagrant also runs without an active graphical session, so it checks filesystem
convergence rather than the visible resolution. Runtime display behavior is
exercised by the workstation pipeline that includes the package, GPU, Xorg, and
display-manager roles together.

All Ansible and Molecule operations are run through the project's remote VM or
CI workflow, not on the local workstation.
