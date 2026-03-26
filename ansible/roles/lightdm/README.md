# lightdm

Deploys LightDM display manager configuration, resolution script, and service state from a dotfiles source directory.

> **Note:** This role does **not** install the `lightdm` package. It assumes LightDM is already present on the system (installed via a separate role or package manager). The molecule scenarios handle installation in their `prepare.yml`.

## Execution flow

0. **Enabled check** — entire role skipped if `lightdm_enabled: false`
1. **Assert supported OS** — fails immediately if `ansible_facts['os_family']` is not in `_lightdm_supported_os` (Archlinux, Debian, RedHat, Void, Gentoo)
2. **Load OS vars** (`vars/<os_family>.yml`) — loads `_lightdm_service` map keyed on init system (`systemd`, `runit`, `openrc`, `s6`, `dinit`)
3. **Validate source dir** — stats `lightdm_source_dir`; fails if path does not exist or is not a directory
4. **Create config directories** — ensures `/etc/lightdm/lightdm.conf.d/` exists (root:root 0755). Idempotent.
5. **Deploy config files** — copies each entry from `lightdm_system_files` from `lightdm_source_dir` to the destination path with the declared owner, group, and mode. A changed file marks the task `changed`. All files are always deployed regardless of `lightdm_enable_service`.
6. **Enable and start service** — runs `ansible.builtin.service` with name from `_lightdm_service[service_mgr]`; skipped if `lightdm_enable_service: false`
7. **Verify** (`tasks/verify.yml`) — asserts config directory exists, all deployed files have correct owner/group/mode/content, and the service is enabled (systemd only, skipped inside Docker)
8. **Report** — writes execution report via `common/report_phase.yml` + `common/report_render.yml`

## Variables

### Configurable (`defaults/main.yml`)

Override via `group_vars/` or `host_vars/`, never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `lightdm_enabled` | `true` | safe | Set `false` to skip this role entirely on a specific host. |
| `lightdm_source_dir` | `{{ dotfiles_base_dir \| default(lookup('env', 'REPO_ROOT') ~ '/dotfiles', true) }}` | safe | Absolute path to the dotfiles source directory on the remote host. Must exist and contain config files under `etc/lightdm/lightdm.conf.d/`. |
| `lightdm_enable_service` | `true` | safe | Enable and start the LightDM service. Set `false` in headless or container environments. |
| `lightdm_system_files` | See below | careful | List of `{src, dest, owner, group, mode}` objects. Changing paths or permissions may break LightDM startup or greeter authentication. |

### `lightdm_system_files` default value

```yaml
lightdm_system_files:
  - src: "etc/lightdm/lightdm.conf.d/10-config.conf"
    dest: "/etc/lightdm/lightdm.conf.d/10-config.conf"
    owner: root
    group: root
    mode: "0644"
  - src: "etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    dest: "/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    owner: lightdm
    group: lightdm
    mode: "0755"
```

### Internal mappings (`vars/`)

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | `_lightdm_service` map — service name per init system on Arch | Adding init system support for Arch |
| `vars/debian.yml` | `_lightdm_service` map for Debian / Ubuntu | Adding init system support for Debian |
| `vars/redhat.yml` | `_lightdm_service` map for RedHat / Fedora | Adding init system support for RedHat |
| `vars/void.yml` | `_lightdm_service` map for Void Linux | Adding init system support for Void |
| `vars/gentoo.yml` | `_lightdm_service` map for Gentoo | Adding init system support for Gentoo |

## Examples

### Pointing at a chezmoi dotfiles checkout

```yaml
# In host_vars/<hostname>/lightdm.yml:
lightdm_source_dir: /home/user/.local/share/chezmoi
```

The role will read `etc/lightdm/lightdm.conf.d/10-config.conf` and `add-and-set-resolution.sh` from that path.

### Disabling service management (initial provisioning or containers)

```yaml
# In host_vars/<hostname>/lightdm.yml:
lightdm_enable_service: false
```

Files are still deployed; only the `Enable and start LightDM service` step is skipped.

### Deploying additional config files

```yaml
# In group_vars/workstations/lightdm.yml:
lightdm_system_files:
  - src: "etc/lightdm/lightdm.conf.d/10-config.conf"
    dest: "/etc/lightdm/lightdm.conf.d/10-config.conf"
    owner: root
    group: root
    mode: "0644"
  - src: "etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    dest: "/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    owner: lightdm
    group: lightdm
    mode: "0755"
  - src: "etc/lightdm/lightdm.conf.d/50-greeter.conf"
    dest: "/etc/lightdm/lightdm.conf.d/50-greeter.conf"
    owner: root
    group: root
    mode: "0644"
```

## Cross-platform details

LightDM uses the same service name and config directory on all supported distros.

| Aspect | Arch Linux | Ubuntu / Debian | RedHat / Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|-----------------|------------|--------|
| Service name | `lightdm` | `lightdm` | `lightdm` | `lightdm` | `lightdm` |
| Config dir | `/etc/lightdm/lightdm.conf.d/` | `/etc/lightdm/lightdm.conf.d/` | `/etc/lightdm/lightdm.conf.d/` | `/etc/lightdm/lightdm.conf.d/` | `/etc/lightdm/lightdm.conf.d/` |
| Init system | systemd | systemd | systemd | runit | openrc |

Init-system dispatch uses `_lightdm_service[ansible_facts['service_mgr']] | default('lightdm')`. If a new init system is added, update the relevant `vars/<os>.yml` file.

## Logs

LightDM writes logs via the init system — there are no separate role-managed log files.

| Source | Path / Command | Contents | Rotation |
|--------|---------------|----------|----------|
| systemd journal | `journalctl -u lightdm.service` | Start/stop events, greeter errors, session auth failures | System journal rotation (default 4GB or 1 month) |
| X server log | `/var/log/Xorg.0.log` or `~/.local/share/xorg/Xorg.0.log` | X display server events, screen setup, driver messages | Not rotated automatically — grows on every session |
| LightDM log | `/var/log/lightdm/lightdm.log` | Greeter selection, display setup script output, seat configuration | Not rotated — truncated on restart |
| Display setup | `/var/log/lightdm/lightdm.log` | Output from `add-and-set-resolution.sh` (set -x trace) | Same as above |

### Reading the logs

- **LightDM won't start:** `journalctl -u lightdm.service -n 100` — look for "Failed to start" or script errors
- **Resolution script not running:** `grep display-setup /var/log/lightdm/lightdm.log` — confirms script is called and shows xrandr output
- **Greeter fails to appear:** `cat /var/log/lightdm/lightdm.log | grep -i error` — greeter binary missing or seat misconfiguration

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | `ansible_facts['os_family']` is not one of the five supported families | Add the OS to `_lightdm_supported_os` in `defaults/main.yml` and create a matching `vars/<family>.yml` |
| Role fails at "Assert dotfiles source directory exists" | `lightdm_source_dir` path does not exist on the remote | Set `lightdm_source_dir` to the correct path in `host_vars/` or ensure dotfiles are checked out before this role runs |
| LightDM won't start after deploy | `journalctl -u lightdm.service -n 50` | Check greeter binary (`nody-greeter` or other) is installed; `greeter-session=` in config must match an installed greeter |
| Infinite restart loop on login | `cat /var/log/lightdm/lightdm.log \| grep display-setup` | `add-and-set-resolution.sh` exited non-zero; script must end with `exit 0` regardless of xrandr errors |
| Config file deployed with wrong ownership | Verify task fails with ownership mismatch | The `lightdm` user/group may not exist if the package was not installed; run package install before this role |
| Service is `masked` after converge | `systemctl status lightdm.service` shows masked | Unmask: `systemctl unmask lightdm.service` — may happen if another display manager was previously default |
| Idempotence failure on second converge | Molecule reports `changed` tasks on second run | Check if `lightdm_source_dir` content is being modified between runs (e.g., chezmoi re-renders files) |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing task logic, templates, or variables | File deployment, ownership, content assertions, idempotence on Arch Linux |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic or service management | Real init system, Arch + Ubuntu matrix, service enablement |

```bash
cd ansible/roles/lightdm

# Fast Docker test (Arch Linux container)
molecule test -s docker

# Cross-platform Vagrant test (Arch + Ubuntu VMs, requires libvirt)
molecule test -s vagrant
```

### Success criteria

- All steps complete: `syntax → create → prepare → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` on second run
- Verify step: all assertions pass (`quiet: true` suppresses passing lines; failures are explicit)
- Final line: no `failed` tasks

### What the tests verify

| Category | Verified by molecule/shared/verify.yml | Verified by tasks/verify.yml |
|----------|----------------------------------------|------------------------------|
| Package | `lightdm` package in `ansible_facts.packages` | — |
| Config directory | `/etc/lightdm/lightdm.conf.d/` exists | Yes |
| 10-config.conf | exists, root:root 0644, `[Seat:*]`, `greeter-session=`, references script | Yes |
| add-and-set-resolution.sh | exists, lightdm:lightdm 0755, `#!/bin/bash`, `xrandr`, `exit 0` | Yes |
| Service | `systemctl is-enabled lightdm.service` → `enabled` (skipped in Docker) | Yes |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `lightdm package not found` in verify | Package not installed; prepare.yml ran before cache update | Run `molecule destroy && molecule test -s docker` to rebuild from scratch |
| `Assertion failed: /etc/lightdm/lightdm.conf.d missing` | Converge failed silently before directory creation | Check converge output for the "Assert dotfiles source directory exists" step |
| Idempotence failure on `Deploy LightDM configuration files` | Source file timestamp or content differs on second run | Verify `/tmp/dotfiles` fixture files are not recreated by prepare on second converge |
| `lightdm.service is not enabled` in verify | Service task skipped due to `skip-tags` or `when` condition | Confirm `lightdm_enable_service: true` and that `service` tag is not in `skip-tags` |
| Vagrant: `Python not found` | Bootstrap playbook missing or Arch `python` package absent | Check `prepare-vagrant.yml` exists in `molecule/shared/` and includes raw Python install |
| `OS family ... is not supported` | Vagrant platform OS family is not in `_lightdm_supported_os` | Add the OS family to defaults and create a vars file |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `lightdm` | Entire role | Full apply |
| `display` | Entire role (alias) | Same as `lightdm` |
| `service` | Enable/start service step only | Restart lightdm without re-deploying config files |
| `report` | Reporting tasks only | Re-generate execution report |

```bash
# Restart lightdm without re-deploying files
ansible-playbook playbook.yml --tags service

# Apply full role
ansible-playbook playbook.yml --tags lightdm
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with safety levels | No — override via inventory |
| `vars/archlinux.yml` | Service name map per init system (Arch) | Only when adding init system support |
| `vars/debian.yml` | Service name map per init system (Debian/Ubuntu) | Only when adding init system support |
| `vars/redhat.yml` | Service name map per init system (RedHat/Fedora) | Only when adding init system support |
| `vars/void.yml` | Service name map per init system (Void) | Only when adding init system support |
| `vars/gentoo.yml` | Service name map per init system (Gentoo) | Only when adding init system support |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/verify.yml` | Post-deploy self-check assertions | When changing verification logic |
| `meta/main.yml` | Galaxy metadata and supported platforms | When adding distro support |
| `molecule/docker/` | Docker test scenario (Arch Linux container) | When changing Docker-specific test setup |
| `molecule/vagrant/` | Vagrant test scenario (Arch + Ubuntu VMs) | When changing cross-platform test setup |
| `molecule/shared/` | Shared converge and verify playbooks | When changing test coverage |
