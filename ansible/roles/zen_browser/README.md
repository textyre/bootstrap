# zen_browser

Installs [Zen Browser](https://zen-browser.app/) from the AUR on Arch Linux, optionally sets it as the system default browser via `xdg-settings`, and verifies the installation.

## Execution flow

1. **Platform assert** — checks `ansible_facts['os_family']` against `_zen_browser_supported_os`; fails immediately with a clear message on any non-Arch host
2. **Refresh pacman cache** — runs `pacman -Sy` to ensure the package database is current (`molecule-notest` — skipped in CI containers)
3. **Check install state** — probes `which zen-browser`; if binary exists, AUR install steps are skipped entirely (idempotent)
4. **Check yay** — verifies `yay --version`; fails with a human-readable message if yay is missing
5. **Create SUDO_ASKPASS helper** — writes `/tmp/.ansible_sudo_askpass_zen` only when `ansible_become_password` is defined and browser is not yet installed; file is `0700` and `no_log: true`
6. **Install via yay** — runs `yay -S --needed --noconfirm {{ zen_browser_aur_package }}`; `changed_when` detects idempotency via yay's "nothing to do" output
7. **Remove SUDO_ASKPASS helper** — immediately deletes `/tmp/.ansible_sudo_askpass_zen` after installation
8. **Verify** (`tasks/verify.yml`) — checks binary in PATH, pacman registration, desktop entry existence, and SUDO_ASKPASS cleanup
9. **Set default browser** — runs `xdg-settings set default-web-browser {{ zen_browser_desktop_file }}` only when `zen_browser_set_default: true` and not already set; requires `DISPLAY`
10. **Report** — emits structured execution report via `common/report_phase.yml` + `report_render.yml`

### Handlers

This role has no handlers.

## Variables

### Configurable (`defaults/main.yml`)

Override via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `zen_browser_enabled` | `true` | safe | Set `false` to skip this role entirely without errors |
| `zen_browser_aur_package` | `zen-browser-bin` | safe | AUR package name to install |
| `zen_browser_user` | `{{ ansible_facts['env']['SUDO_USER'] \| default(ansible_facts['user_id']) }}` | careful | Non-root user for `yay`/`makepkg` builds. Must be an existing user with sudo access |
| `zen_browser_set_default` | `true` | safe | Set Zen Browser as default browser via `xdg-settings`; requires `DISPLAY` — set `false` in headless environments |
| `zen_browser_desktop_file` | `zen.desktop` | careful | `.desktop` filename passed to `xdg-settings set default-web-browser`. Must match the file installed by the AUR package |

### Internal (`defaults/main.yml`)

| Variable | Value | Purpose |
|----------|-------|---------|
| `_zen_browser_supported_os` | `[Archlinux]` | OS family allowlist for the preflight assert. Do not override — zen_browser depends on AUR which only exists on Arch |

## Examples

### Disable the role on a specific host

```yaml
# host_vars/<hostname>/zen_browser.yml
zen_browser_enabled: false
```

### Install without setting as default browser (headless/server)

```yaml
# group_vars/headless/zen_browser.yml
zen_browser_set_default: false
```

### Pin a specific AUR package variant

```yaml
# host_vars/workstation/zen_browser.yml
zen_browser_aur_package: "zen-browser"   # source build instead of -bin
```

### Full example playbook

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

## Supported platforms

| OS | Support |
|----|---------|
| Arch Linux | Full — AUR via yay |
| Ubuntu / Fedora / Void / Gentoo | Not supported — role hard-fails on preflight assert |

## Logs

### Ansible output

This role produces no persistent log files. All output is via Ansible task output and the structured execution report (step 10).

| Output | Location | Contents |
|--------|----------|----------|
| Install log | Ansible task output (`zen_browser_install`) | yay stdout: package download, build, install progress |
| Execution report | Ansible debug task (last step) | Structured table: Install phase, Set default phase |

### Reading the output

- **Install failed silently**: check `zen_browser_install.stdout` in task output — yay reports errors inline
- **Already installed**: look for the "zen-browser already installed at ..." debug message — AUR steps are skipped
- **Verify failed**: read the `fail_msg` from the failing assert — it includes the install log excerpt and remediation hint

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at platform assert | `ansible_facts['os_family']` is not `Archlinux` | This role supports only Arch Linux. Do not run on Ubuntu/Fedora/Void/Gentoo |
| `yay не найден` at startup | yay is not installed on the host | Run the `yay` role before `zen_browser` in your playbook |
| `zen-browser binary not found` after install | AUR build failed or was silently skipped | Check `zen_browser_install.stdout_lines` in task output; re-run with `-vvv` for full yay output |
| Idempotence failure: install always `changed` | `changed_when` condition not matching yay output | Verify yay outputs "there is nothing to do" — may differ between yay versions; check `yay --version` |
| `xdg-settings set` fails | `DISPLAY` not set or D-Bus unavailable | Set `zen_browser_set_default: false` in headless environments; test only in real desktop sessions |
| SUDO_ASKPASS assert fails | `/tmp/.ansible_sudo_askpass_zen` still present | Delete manually: `rm -f /tmp/.ansible_sudo_askpass_zen`; investigate why the remove task was skipped |
| `makepkg: You should not run makepkg as root` | `zen_browser_user` resolved to `root` | Set `zen_browser_user` explicitly to a non-root user in inventory |

## Testing

Both scenarios are required (TEST-002). Use Docker for fast feedback, Vagrant for full validation on a real VM.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| `default` (localhost) | `molecule test` | Fast iteration on your own Arch system | Full install, idempotence, verify on real hardware |
| `docker` | `molecule test -s docker` | CI / isolated environment | AUR install in Arch container, idempotence, verify |
| `vagrant` | `molecule test -s vagrant` | Before merge, after OS-specific changes | Real Arch VM, real pacman/yay, full install cycle |

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing — yay reports "nothing to do")
- Verify step: all asserts pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Checked | Source |
|----------|---------|--------|
| Binary | `zen-browser` is in PATH at `/usr/bin/zen-browser` | `tasks/verify.yml` + `molecule/shared/verify.yml` |
| Package | `pacman -Qi zen-browser-bin` exits 0 | `tasks/verify.yml` |
| Desktop entry | `/usr/share/applications/zen.desktop` exists with `[Desktop Entry]`, `Type=Application`, `Exec=`, `Name=` | `molecule/shared/verify.yml` |
| Security | `/tmp/.ansible_sudo_askpass_zen` is absent after install | `tasks/verify.yml` + `molecule/shared/verify.yml` |
| Platform | `os_family == 'Archlinux'` | `molecule/shared/verify.yml` |

### Docker scenario setup (`molecule/docker/prepare.yml`)

Before converge, the Docker scenario:
1. Refreshes the pacman cache
2. Installs `base-devel` and `git` (required to build AUR packages)
3. Creates a non-root `testuser` with passwordless sudo
4. Clones and builds `yay` from AUR as `testuser`

The converge forces `zen_browser_set_default: false` because `xdg-settings` requires a running `DISPLAY`.

### Vagrant scenario setup (`molecule/vagrant/prepare.yml`)

Before converge, the Vagrant scenario:
1. Force-refreshes the pacman package database (via shared `prepare-vagrant.yml`)
2. Installs `base-devel` and `git`
3. Creates `testuser` with passwordless sudo
4. Clones and builds `yay` from AUR as `testuser`

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `yay не найден` | prepare.yml didn't install yay successfully | Run full sequence: `molecule test`, not just `molecule converge` |
| Idempotence failure on install task | yay output format changed between versions | Check yay version; verify "nothing to do" string matches `changed_when` |
| `zen-browser binary not found` assert fails | AUR build failed in container | Rebuild: `molecule destroy -s docker && molecule test -s docker`; check DNS in container |
| `Desktop entry does not exist` | zen-browser-bin package didn't install `.desktop` | Run: `pacman -Ql zen-browser-bin \| grep desktop` to verify path |
| Vagrant: `Python not found` | Base image bootstrap issue | Shared `prepare-vagrant.yml` handles Python; check import path in prepare.yml |
| Vagrant: yay build fails | Network blocked or `base-devel` missing | Verify `base-devel` install step ran; check internet connectivity on the VM |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `zen_browser` | Entire role | Full apply |
| `browser` | Entire role (alias) | Group all browser roles together |
| `configure` | Default-browser tasks only | Re-run `xdg-settings` without reinstalling |
| `report` | Logging/report tasks only | Re-generate execution report |
| `molecule-notest` | AUR install tasks | Skipped by Docker scenario provisioner |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings and `_zen_browser_supported_os` | No — override via inventory |
| `tasks/main.yml` | Main orchestration: platform assert, install, verify, report | No |
| `tasks/verify.yml` | Post-install verification: binary, package, desktop entry, security | No |
| `molecule/default/molecule.yml` | Localhost scenario (fast iteration on real Arch system) | No |
| `molecule/docker/molecule.yml` | Docker CI scenario | No |
| `molecule/docker/prepare.yml` | Docker pre-converge: base-devel, testuser, yay | Only to add Docker-specific setup |
| `molecule/vagrant/molecule.yml` | Vagrant full-VM scenario | No |
| `molecule/vagrant/prepare.yml` | Vagrant pre-converge: base-devel, testuser, yay | Only to add VM-specific setup |
| `molecule/shared/converge.yml` | Shared converge playbook (all scenarios) | Only to change role vars for tests |
| `molecule/shared/verify.yml` | Shared verify playbook (all scenarios) | Only to add new verification steps |

## License

MIT
