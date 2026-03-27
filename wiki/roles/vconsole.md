# Vconsole Role

Configure console (TTY) keymap, fonts, and GPM daemon (mouse support in TTY).

## Supported Platforms

| OS Family | Init Systems | Package Manager | Status |
|-----------|--------------|-----------------|--------|
| Archlinux | systemd, runit, openrc, s6*, dinit* | pacman | ✅ Full |
| Debian | systemd | apt | ✅ Full |
| RedHat | systemd | dnf | ✅ Full |
| Void | runit | xbps | ✅ Full |
| Gentoo | openrc | portage | ✅ Full |

*s6, dinit: stub implementations with debug messages (not yet fully supported)

## Variables

### Console Keymap (Required)

```yaml
vconsole_console: "us"                              # TTY keymap (e.g. "us", "de", "fr")
vconsole_console_map_src: ""                        # Optional: path to custom .map file in your repo
vconsole_console_font: ""                           # Optional: console font (e.g. "ter-v16n", "lat2-16")
vconsole_console_font_map: ""                       # Optional: font map (e.g. "8859-2")
vconsole_console_font_unimap: ""                    # Optional: unicode map file
```

### GPM Daemon (General Purpose Mouse)

```yaml
vconsole_gpm_enabled: true                         # Enable mouse in TTY
```

## Dependencies

- `common` role (for logging/reporting)
- No external role dependencies

## Tags

- `vconsole` — main role tasks
- `report` — reporting tasks (skip with `--skip-tags report`)

## How It Works

1. **Validate** — check configuration
2. **Prepare custom keymap** — copy .map file if specified
3. **Install font** — install distro-specific console font package
4. **Configure keymap** — dispatch to init-specific task:
   - systemd: write `/etc/vconsole.conf`
   - openrc: write `/etc/conf.d/keymaps`
   - runit: write `/etc/rc.conf`
   - s6/dinit: stub (debug message)
5. **Configure GPM** — install and start mouse daemon (if enabled)
6. **Verify** — check keymap, font, GPM service state
7. **Report** — log phases to common role reporting system

## Execution Flow

```
validate
  ↓
prepare custom .map file
  ↓
install font package
  ↓
configure keymap (init-dispatch)
  ↓
configure GPM daemon
  ↓
verify configuration
  ↓
report results
```

## Architecture

**Per-Distro Package Variables:** Each OS family has its own `vars/FAMILY.yml`:
- `_vconsole_font_package` — package providing console fonts
- `_vconsole_gpm_package` — GPM daemon package

**Init System Dispatch:** Uses `with_first_found` to load init-specific tasks:
- `tasks/init/{systemd,openrc,runit,s6,dinit}.yml` — configure keymap
- `tasks/verify/{systemd,openrc,runit,s6,dinit}.yml` — verify configuration

## Examples

### Basic keymap only

```yaml
- name: Configure console keymap
  ansible.builtin.include_role:
    name: vconsole
  vars:
    vconsole_console: "de"
```

### With font (Arch)

```yaml
- name: Configure console with font
  ansible.builtin.include_role:
    name: vconsole
  vars:
    vconsole_console: "us"
    vconsole_console_font: "ter-v16n"
    vconsole_console_font_map: "8859-2"
```

### With custom keymap file

```yaml
- name: Configure with custom keymap
  ansible.builtin.include_role:
    name: vconsole
  vars:
    vconsole_console: "custom"
    vconsole_console_map_src: "files/my-custom.map"
```

## Logs & Audit Events

All phases are logged via `common` role reporting:
- Console keymap configuration (init system, keymap value)
- Console font installation (font name, font_map)
- GPM daemon status (enabled/disabled)
- Verification phase summary (keymap, font, init)

Search for `_vconsole_phases` fact in execution reports.

## Troubleshooting

### Font not applied (Docker)

Console fonts are a Linux kernel feature. Docker containers may not support `setfont`. The role checks `vconsole_console_font` and skips installation on unsupported OS families (e.g., Ubuntu).

**Workaround:** Set `vconsole_console_font: ""` on non-Arch platforms.

### GPM not running (Docker/Containers)

GPM requires device access (`/dev/input`). The role detects virtualization and skips service start on `docker`, `container`, `podman` platforms. Package remains installed.

**Check:** `ansible_facts['virtualization_type']` in verify logs.

### Keymap not in localectl (non-Arch)

OpenRC and runit systems write keymap config but don't integrate with `systemd-localed`. The role verifies config files exist with correct content, not system-wide `localectl` state.

## Testing

**Docker:** `molecule test -s docker` — tests systemd on Archlinux and Ubuntu

**Vagrant:** `molecule test -s vagrant` — tests systemd/runit/openrc on real VMs

**Scenarios:**
- `default` — localhost (vault password required)
- `docker` — Archlinux (systemd), Ubuntu (systemd)
- `vagrant` — Archlinux (runit), Ubuntu (systemd)

See `molecule/` directory for scenario configurations.
