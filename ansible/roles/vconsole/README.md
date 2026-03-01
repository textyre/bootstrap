# vconsole

Configures console (TTY) keymap, optional console font, and optional GPM (mouse in TTY).
Dispatches by init system — no conditional branches in tasks; uses `with_first_found` to
select the correct init-specific task file.

## Requirements

- Ansible 2.15+
- `become: true` (root access required)
- `kbd` package (provides `loadkeys`, `setfont`) — install via the `prepare.yml` in molecule
  or as a role dependency on target systems

## Supported distributions

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo.

## Supported init systems

| Init system | Keymap file | Font file |
|---|---|---|
| systemd | `/etc/vconsole.conf` (`KEYMAP=`, `FONT=`, `FONT_MAP=`, `FONT_UNIMAP=`) | same file |
| openrc | `/etc/conf.d/keymaps` | `/etc/conf.d/consolefont` |
| runit | `/etc/rc.conf` (`KEYMAP=`, `FONT=`) | same file |

## Role variables

| Variable | Default | Description |
|---|---|---|
| `vconsole_console` | `"us"` | Console keymap identifier (e.g. `us`, `ru`, `de`) |
| `vconsole_console_map_src` | `""` | Optional: local path to a custom `.map` file in your repo |
| `vconsole_console_font_package` | `"terminus-font"` | Package providing console fonts (installed when `vconsole_console_font` is set) |
| `vconsole_console_font` | `""` | Console font name (e.g. `ter-v16n`, `lat2-16`). Empty = no font configured |
| `vconsole_console_font_map` | `""` | Font map (e.g. `8859-2`) (systemd only) |
| `vconsole_console_font_unimap` | `""` | Unicode map file (systemd only) |
| `vconsole_gpm_enabled` | `true` | Install GPM package and enable/start service on non-container targets. In containerized Molecule environments, the role may skip service start while still installing the package (set `false` for headless/VM environments — GPM requires `/dev/input/mice`) |

## Example playbook

```yaml
- name: Configure console keymap and font
  hosts: workstations
  become: true
  roles:
    - role: vconsole
```

With a custom font (Arch Linux):

```yaml
- name: Configure console with Terminus font
  hosts: workstations
  become: true
  roles:
    - role: vconsole
      vars:
        vconsole_console: "us"
        vconsole_console_font: "ter-v16n"
        vconsole_console_font_package: "terminus-font"
        vconsole_gpm_enabled: false
```

## Notes

- **GPM and headless VMs**: GPM requires `/dev/input/mice` which is absent in most VMs.
  Set `vconsole_gpm_enabled: false` for Vagrant/cloud targets.
- **Ubuntu font packages**: Ubuntu does not ship `terminus-font`. Use `fonts-terminus` or
  leave `vconsole_console_font` empty. The keymap configuration via `/etc/vconsole.conf`
  works on Ubuntu (systemd reads it), but is non-standard compared to `console-setup`.
- **Handler**: `apply vconsole` restarts `systemd-vconsole-setup.service` on systemd,
  or runs `loadkeys`/`setfont` directly on openrc/runit.

## Testing

### molecule scenarios

| Scenario | Driver | Platforms | Notes |
|---|---|---|---|
| `default` | localhost | host system | Uses vault, shared/ playbooks |
| `docker` | Docker | Arch systemd container | Full flow: keymap + font + GPM-disabled |
| `vagrant` | Vagrant/KVM | Arch VM + Ubuntu Noble VM | Cross-platform: Arch (full), Ubuntu (keymap only + localectl) |

Run locally (requires molecule and the appropriate driver):

```bash
cd ansible/roles/vconsole

# Docker scenario (fast, Arch only)
molecule test -s docker

# Vagrant scenario (cross-platform, requires libvirt)
molecule test -s vagrant

# Syntax check only
molecule syntax -s vagrant
```

## License

MIT
