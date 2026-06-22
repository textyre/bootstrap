# vconsole

Configures console (TTY) keymap, optional console font, and optional GPM (mouse in TTY).
Dispatches by init system using `include_tasks` with init-specific task files.

## Requirements

- Ansible 2.15+
- `become: true` (root access required)
- `kbd` package (provides `loadkeys`, `setfont`) — required for openrc/runit init systems

## Supported distributions

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo.

## Supported init systems

| Init system | Keymap file | Status |
|---|---|---|
| systemd (Arch/Fedora/etc.) | `/etc/vconsole.conf` (`KEYMAP=`, `FONT=`, `FONT_MAP=`, `FONT_UNIMAP=`) | ✅ Full |
| systemd (Debian/Ubuntu) | `/etc/default/keyboard` (`XKBLAYOUT=`), generated `/usr/share/keymaps/xkb/*.map` | ✅ Full |
| openrc | `/etc/conf.d/keymaps` | ✅ Full |
| runit | `/etc/rc.conf` (`KEYMAP=`, `FONT=`) | ✅ Full |
| s6 | (stub) | ⚠️ Debug message only |
| dinit | (stub) | ⚠️ Debug message only |

## Role variables

| Variable | Default | Description |
|---|---|---|
| `vconsole_console` | `"us"` | Console keymap identifier (e.g. `us`, `ru`, `de`) |
| `vconsole_console_map_src` | `""` | Optional: local path to a custom `.map` file in your repo |
| `vconsole_console_font` | `"ter-v16n"` | Console font name (e.g. `ter-v16n`, `lat2-16`) |
| `vconsole_console_font_map` | `""` | Font map (e.g. `8859-2`) (systemd only) |
| `vconsole_console_font_unimap` | `""` | Unicode map file (systemd only) |
| `vconsole_gpm_enabled` | `true` | Install GPM package and enable/start service on non-container targets |

**Note:** Font package names are distro-specific (managed by `vars/DISTRO_FAMILY.yml`):
- Arch: `terminus-font`, `gpm`
- Debian/Ubuntu: `fonts-terminus`, `gpm`, plus `console-setup-linux`,
  `console-setup`, and `kbd` for the systemd console keymap backend
- RedHat/Fedora: `terminus-fonts`, `gpm`
- Void: `terminus-font`, `gpm`
- Gentoo: `sys-fonts/terminus-font`, `sys-libs/gpm`

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
        vconsole_gpm_enabled: false
```

## Notes

- **GPM and headless VMs**: GPM requires `/dev/input/mice` which is absent in most VMs.
  Set `vconsole_gpm_enabled: false` for Vagrant/cloud targets.
- **Ubuntu/Debian systemd**: Ubuntu and Debian use `keyboard-configuration` /
  `console-setup`, so this role manages `/etc/default/keyboard` instead of
  `/etc/vconsole.conf`. The `systemd-vconsole-setup.service` unit is not part
  of the Ubuntu 24.04 test targets.
- **Apply behavior**: systemd-vconsole targets restart
  `systemd-vconsole-setup.service`; Debian-family systemd targets install the
  `console-setup` backend, generate a kbd-compatible map with `ckbcomp`, set
  `VC Keymap` through `systemd-localed`, and restart `keyboard-setup.service`.
  OpenRC/runit targets run `loadkeys`/`setfont` directly.

## Test Cases

### Scenario: `docker`

**Driver:** Docker (via molecule)
**Platforms:** Archlinux (systemd), Ubuntu (systemd)

| Test Case | Keymap | Font | GPM | OS | Init |
|---|---|---|---|---|---|
| Arch font + keymap | us | ter-v16n | enabled | Arch | systemd |
| Ubuntu keymap only | us | (none) | enabled | Ubuntu | systemd |

### Scenario: `vagrant`

**Driver:** Vagrant/KVM (libvirt)
**Platforms:** Archlinux (runit), Ubuntu (systemd)

| Test Case | Keymap | Font | GPM | OS | Init |
|---|---|---|---|---|---|
| Arch (runit) | us | ter-v16n | enabled | Arch | runit |
| Ubuntu (systemd) | us | (none) | enabled | Ubuntu | systemd |

### Running Tests

```bash
cd ansible/roles/vconsole

# Docker scenario (fast, ~2min, Arch + Ubuntu systemd)
molecule test -s docker

# Vagrant scenario (slower, ~10min, Arch runit + Ubuntu systemd)
molecule test -s vagrant

# Syntax check only
molecule syntax -s vagrant

# Debug a failed test
molecule test -s docker --destroy=never
# then: molecule login -s docker --host Archlinux-systemd
```

### Test Coverage

- ✅ Keymap configuration (systemd)
- ✅ Font installation and configuration (Arch only)
- ✅ GPM service state verification (enabled)
- ✅ Idempotency (converge runs twice without state changes)
- ✅ Cross-platform consistency (Arch + Ubuntu)

## License

MIT
