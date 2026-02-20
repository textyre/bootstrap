# keymap role: hardening & completeness design

Date: 2026-02-20

## Context

The `ansible/roles/keymap` role configures console (TTY) keyboard layout and font
across systemd, OpenRC (Gentoo), and runit (Void Linux) systems.

Two categories of problems were identified: reliability bugs and missing functionality.

## Problems

### Reliability

1. `failed_when: false` in openrc/runit handler silently swallows `loadkeys` errors
2. Handler for systemd restarts `systemd-vconsole-setup.service` but uses direct
   `loadkeys`/`setfont` — these only apply to the current TTY, not all virtual consoles
3. validate only checks that `keymap_console` is non-empty — invalid values pass
4. No guard: `font_map` or `font_unimap` can be set without `font`
5. Molecule: `_test_keymap: "us"` hardcoded, not tied to role variable
6. Molecule: no `idempotence` step in test_sequence
7. verify for openrc/runit checks only presence of string, not exact value

### Missing functionality

8. Font (`keymap_console_font` etc.) only works for systemd via vconsole.conf;
   openrc and runit have no font handling
9. Font package is never installed — role writes font name but does not ensure
   the package exists
10. No GPM support (mouse in TTY)
11. Alpine Linux declared in `meta/main.yml` but not actually supported
    (busybox uses `loadkmap`, incompatible format)
12. Template for systemd overwrites entire vconsole.conf — unsafe if other roles
    also manage that file

## Design

### Variables (`defaults/main.yml`)

```yaml
keymap_console: "us"                        # required, non-empty
keymap_console_map_src: ""                  # optional: local path to custom .map file

keymap_console_font_package: "terminus-font" # package to install
keymap_console_font: ""                     # empty = skip font entirely
keymap_console_font_map: ""
keymap_console_font_unimap: ""

keymap_gpm_enabled: true                    # mouse in TTY
```

**Custom keymap file support:** if `keymap_console_map_src` is set, the role copies
the `.map` file to `/usr/local/share/kbd/keymaps/` on the target host and sets
`KEYMAP=` to the full path instead of the keymap name. This allows custom remappings
(e.g. CapsLock → Escape, include base layout + overrides) stored in the repository.

Example `.map` file:
```
#include "us"
keycode 58 = Escape   # remap CapsLock to Escape
```

If `keymap_console_map_src` is empty (default), `KEYMAP={{ keymap_console }}` is used
(standard keymap name from `/usr/share/kbd/keymaps/`).

Font is opt-in: if `keymap_console_font` is empty, no package is installed
and no font lines are written.

### Validate (`tasks/validate/main.yml`)

- `keymap_console` defined and non-empty (existing)
- `keymap_console_font_map` or `keymap_console_font_unimap` set → `keymap_console_font` must be set

### Tasks structure (`tasks/main.yml`)

Order: validate → custom map → font package → configure → gpm → verify → report

New task files:
- `tasks/map.yml` — create `/usr/local/share/kbd/keymaps/`, copy `keymap_console_map_src` (when set)
- `tasks/font.yml` — install `keymap_console_font_package` (all init systems, only when font set)
- `tasks/gpm.yml` — install gpm, enable and start service (all init systems, when `keymap_gpm_enabled`)

### Configure: lineinfile instead of template

Replace `vconsole.conf.j2` template with `lineinfile` tasks for systemd.
Rationale: `lineinfile` does not overwrite lines managed by other roles.

`init/systemd.yml`:
```yaml
# KEYMAP= uses path if map_src set, otherwise keymap name
lineinfile: path=/etc/vconsole.conf  regexp='^KEYMAP='      line='KEYMAP={{ keymap_console_map_dest | default(keymap_console) }}'
lineinfile: path=/etc/vconsole.conf  regexp='^FONT='        line='FONT={{ keymap_console_font }}'        when: font set
lineinfile: path=/etc/vconsole.conf  regexp='^FONT_MAP='    line='FONT_MAP={{ keymap_console_font_map }}' when: font_map set
lineinfile: path=/etc/vconsole.conf  regexp='^FONT_UNIMAP=' line='FONT_UNIMAP={{ ... }}'                 when: font_unimap set
```

`init/openrc.yml` — adds font via `/etc/conf.d/consolefont` when font set.

`init/runit.yml` — adds `FONT=` to `/etc/rc.conf` when font set.

### Handlers (`handlers/main.yml`)

```yaml
# systemd: restart service → applies to ALL virtual consoles
- name: Apply vconsole settings (systemd)
  systemd:
    name: systemd-vconsole-setup.service
    state: restarted
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] == 'systemd'

# openrc/runit: direct commands (no equivalent service)
- name: Apply keymap (openrc/runit)
  command: loadkeys {{ keymap_console }}
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] in ['openrc', 'runit']

- name: Apply font (openrc/runit)
  command: setfont {{ keymap_console_font }}
  listen: "apply keymap"
  when:
    - ansible_facts['service_mgr'] in ['openrc', 'runit']
    - keymap_console_font != ""
```

`failed_when: false` is removed. Errors surface immediately.

### Verify

- systemd: existing `localectl status` check + add check for FONT in `/etc/vconsole.conf`
- openrc/runit: slurp + assert exact value (not just substring presence)
- all: if `keymap_gpm_enabled`, assert gpm service is running

### Molecule

`converge.yml`:
```yaml
vars:
  keymap_console: "us"
  keymap_console_font_package: "terminus-font"
  keymap_console_font: "ter-v16n"
  keymap_gpm_enabled: true
```

`verify.yml`: remove hardcoded `_test_keymap`, use role vars directly.
Add font presence check in vconsole.conf. Add gpm service check.

`molecule.yml` test_sequence:
```yaml
- syntax
- converge
- idempotence
- verify
```

### meta/main.yml

Remove Alpine from platforms list. Supported: ArchLinux, Debian, Ubuntu, EL, Gentoo (OpenRC), Void (runit).

## Out of scope

- Debian/Ubuntu idiom (`/etc/default/keyboard`, `console-setup`) — works via systemd
  path but not idiomatic; separate task if needed later
- Alpine Linux — busybox `loadkmap` incompatible, excluded
- Validating that keymap file exists on filesystem — complex, skipped for now
