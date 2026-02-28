# zen_browser

Installs [Zen Browser](https://zen-browser.app/) from the AUR on Arch Linux, optionally sets it as the system default browser via `xdg-settings`, and verifies the installation.

## What this role does

- [x] Asserts the host is Arch Linux (AUR-only package)
- [x] Verifies `yay` is installed — fails with a clear message if missing
- [x] Installs `zen-browser-bin` via `yay` (idempotent — skipped if already installed)
- [x] Handles `SUDO_ASKPASS` for `ansible_become_password` in non-interactive runs
- [x] Cleans up the temporary `SUDO_ASKPASS` helper after installation
- [x] Verifies the `zen-browser` binary exists at `/usr/bin/zen-browser`
- [x] Optionally sets Zen Browser as the default web browser via `xdg-settings` (requires `DISPLAY`)
- [x] Reports the installation path

## Requirements

- **OS:** Arch Linux only — the role hard-fails on any other OS family
- **AUR helper:** `yay` must be installed before running this role (install with the `yay` role)
- **Privilege escalation:** `become: true` on the play; `ansible_become_password` is required for non-interactive `sudo` inside `makepkg`
- **Ansible:** 2.15+
- **`gather_facts: true`** — required for `ansible_facts['os_family']` and `ansible_facts['env']`

## Role variables

| Variable | Default | Description |
|----------|---------|-------------|
| `zen_browser_aur_package` | `zen-browser-bin` | AUR package name to install |
| `zen_browser_user` | `{{ ansible_facts['env']['SUDO_USER'] \| default(ansible_facts['user_id']) }}` | Non-root user for `yay`/`makepkg` builds |
| `zen_browser_set_default` | `true` | Set Zen Browser as the default web browser via `xdg-settings` |
| `zen_browser_desktop_file` | `zen.desktop` | `.desktop` entry name passed to `xdg-settings set default-web-browser` |

## Dependencies

None. The role declares no Galaxy dependencies.  
Runtime prerequisite: `yay` AUR helper must be installed separately (e.g. via the `yay` role).

## Example playbook

```yaml
- name: Install Zen Browser
  hosts: workstation
  become: true
  gather_facts: true

  roles:
    - role: yay          # must run before zen_browser
    - role: zen_browser
      vars:
        zen_browser_user: "{{ ansible_facts['env']['SUDO_USER'] }}"
        zen_browser_set_default: true
```

To skip setting the default browser (e.g. in headless environments):

```yaml
    - role: zen_browser
      vars:
        zen_browser_set_default: false
```

## Tags

| Tag | Runs |
|-----|------|
| `zen_browser` | All tasks |
| `browser` | All tasks (alias) |
| `configure` | Default-browser tasks only |

## Supported platforms

| OS | Support |
|----|---------|
| Arch Linux | Full |
| Ubuntu / Fedora / Void / Gentoo | Not supported — role hard-fails |

## Testing

### Scenarios

| Scenario | Driver | Platform | Purpose |
|----------|--------|----------|---------|
| `default` | `default` (localhost) | Local Arch system | Fast iteration, full hardware access |
| `docker` | Docker | `arch-systemd` container | CI, full AUR install in isolated container |

Both scenarios share `molecule/shared/converge.yml` and `molecule/shared/verify.yml` — the
assertions are identical across environments.

### Running tests

```bash
# Localhost (default scenario) — runs on your current Arch system
cd ansible/roles/zen_browser
molecule test

# Docker — requires MOLECULE_ARCH_IMAGE or uses ghcr.io/textyre/arch-base:latest
molecule test -s docker

# Syntax check only
molecule syntax
molecule syntax -s docker
```

### What is tested

The shared verify playbook asserts:

- **Platform:** host is Arch Linux (`os_family == 'Archlinux'`)
- **Binary:** `zen-browser` is present in `PATH` at `/usr/bin/zen-browser`
- **Package:** `zen-browser-bin` is registered with pacman (`pacman -Qi`)
- **Desktop entry:** `/usr/share/applications/zen.desktop` exists and contains `[Desktop Entry]`, `Type=Application`, `Exec=`, `Name=`
- **Cleanup:** `/tmp/.ansible_sudo_askpass_zen` was removed after install (no credentials left on disk)

### Docker scenario setup (prepare.yml)

Before converge, the Docker scenario:
1. Updates the pacman cache
2. Installs `base-devel` and `git` (required to build AUR packages)
3. Creates a non-root `testuser` with passwordless sudo
4. Clones and builds `yay` from AUR as `testuser`

The converge overrides `zen_browser_set_default: false` because `xdg-settings` requires a
running `DISPLAY` and fails in headless CI containers.

### Headless CI limitation

`xdg-settings set default-web-browser` calls into D-Bus/XDG infrastructure and requires
`DISPLAY` to be set to a real or virtual display. In headless Docker containers this will
always fail. The converge playbook therefore forces `zen_browser_set_default: false` in both
test scenarios. To test the default-browser flow, run against a real desktop session.

## Known bugs fixed

Two variable name mismatches were corrected during molecule integration:

1. **`changed_when` on install task** — the condition referenced the wrong register variable
   name. Updated to `zen_browser_install` (matching the `register:` on the yay task) so
   idempotency is reported correctly instead of always showing `changed`.

2. **`when` condition on set-default task** — the `stdout` comparison referenced a stale
   variable name instead of `zen_browser_current_default.stdout`. Fixed so the task is
   correctly skipped when Zen Browser is already the default browser.

## License

MIT
