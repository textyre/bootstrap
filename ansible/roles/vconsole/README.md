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

| Init system | Keymap file | Status |
|---|---|---|
| systemd | `/etc/vconsole.conf` (`KEYMAP=`, `FONT=`, `FONT_MAP=`, `FONT_UNIMAP=`) | ✅ Full |
| openrc | `/etc/conf.d/keymaps` | ✅ Full |
| runit | `/etc/rc.conf` (`KEYMAP=`, `FONT=`) | ✅ Full |
| s6 | (stub) | ⚠️ Debug message only |
| dinit | (stub) | ⚠️ Debug message only |

## Role variables

| Variable | Default | Description |
|---|---|---|
| `vconsole_console` | `"us"` | Console keymap identifier (e.g. `us`, `ru`, `de`) |
| `vconsole_console_map_src` | `""` | Optional: local path to a custom `.map` file in your repo |
| `vconsole_console_font` | `""` | Console font name (e.g. `ter-v16n`, `lat2-16`). Empty = no font configured |
| `vconsole_console_font_map` | `""` | Font map (e.g. `8859-2`) (systemd only) |
| `vconsole_console_font_unimap` | `""` | Unicode map file (systemd only) |
| `vconsole_gpm_enabled` | `true` | Install GPM package and enable/start service on non-container targets. In containerized Molecule environments, the role may skip service start while still installing the package (set `false` for headless/VM environments — GPM requires `/dev/input/mice`) |

**Note:** Font package names are distro-specific (managed by `vars/DISTRO_FAMILY.yml`):
- Arch: `terminus-font`, `gpm`
- Debian/Ubuntu: `fonts-terminus`, `gpm`
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

## Test Cases

### Scenario: `docker`

**Driver:** Docker (via molecule)
**Platforms:** Archlinux (systemd), Ubuntu (systemd)

| Test Case | Keymap | Font | GPM | OS | Init | Verifies |
|---|---|---|---|---|---|---|
| Arch font + keymap | us | ter-v16n | disabled | Arch | systemd | vconsole.conf (KEYMAP, FONT, FONT_MAP) |
| Ubuntu keymap only | us | (none) | disabled | Ubuntu | systemd | vconsole.conf (KEYMAP only) |

### Scenario: `vagrant`

**Driver:** Vagrant/KVM (libvirt)
**Platforms:** Archlinux (runit), Ubuntu (systemd)

| Test Case | Keymap | Font | GPM | OS | Init | Verifies |
|---|---|---|---|---|---|---|
| Arch (runit) | us | ter-v16n | disabled | Arch | runit | /etc/rc.conf, localectl |
| Ubuntu (systemd) | us | (none) | disabled | Ubuntu | systemd | vconsole.conf, localectl |

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

- ✅ Keymap configuration across init systems (systemd, openrc, runit)
- ✅ Font installation and configuration (Arch only due to distro-specific packages)
- ✅ GPM service state verification (enabled/disabled, container detection)
- ✅ Idempotency (converge runs twice without state changes)
- ✅ Cross-platform consistency (Arch + Ubuntu)

## License

MIT
