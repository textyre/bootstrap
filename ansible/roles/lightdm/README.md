# lightdm

LightDM display manager configuration deployment — config files, resolution script, and service state.

> **Note:** This role does **not** install the `lightdm` package. It assumes LightDM is already present on the system (either pre-installed or installed via a separate role/task). The docker molecule scenario handles installation in its `prepare.yml`.

## What this role does

- [x] Validates that the dotfiles source directory exists (`lightdm_source_dir`)
- [x] Creates `/etc/lightdm/lightdm.conf.d/` directory with correct ownership
- [x] Deploys `10-config.conf` (root:root, 0644) — LightDM seat configuration with greeter session and display setup script reference
- [x] Deploys `add-and-set-resolution.sh` (lightdm:lightdm, 0755) — xrandr resolution setup script that always exits 0 to prevent LightDM restart loops
- [x] Enables and starts `lightdm.service` (controllable via `lightdm_enable_service`)
- [x] Reports deployment summary (file count, service state)

## Requirements

- `lightdm` package must be installed before this role runs
- Source files must exist under `lightdm_source_dir` at the expected relative paths:
  - `etc/lightdm/lightdm.conf.d/10-config.conf`
  - `etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh`
- Arch Linux (only supported platform per `meta/main.yml`)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `lightdm_source_dir` | `{{ dotfiles_base_dir \| default(lookup('env', 'REPO_ROOT') ~ '/dotfiles', true) }}` | Absolute path to the dotfiles source directory on the remote host. Must exist and contain the config files under `etc/lightdm/lightdm.conf.d/`. |
| `lightdm_enable_service` | `true` | Whether to enable and start `lightdm.service`. Set to `false` in headless/container test environments. |
| `lightdm_system_files` | See defaults | List of file objects `{src, dest, owner, group, mode}` to deploy from `lightdm_source_dir`. |

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

## Dependencies

None.

## Example playbook

```yaml
- name: Configure LightDM
  hosts: workstations
  become: true

  vars:
    dotfiles_base_dir: /home/user/.local/share/chezmoi

  roles:
    - role: lightdm
```

To skip the service management step (e.g., during initial provisioning):

```yaml
- role: lightdm
  vars:
    lightdm_enable_service: false
```

## Tags

| Tag | Effect |
|-----|--------|
| `lightdm` | All tasks |
| `display` | All tasks (alias) |
| `service` | Enable/start service only |

## Testing

Two molecule scenarios are provided.

### `default` (localhost, no containers)

Runs against `localhost` using a local Ansible connection. Requires `lightdm` installed and the dotfiles repository checked out locally.

```bash
cd ansible/roles/lightdm
molecule test           # full cycle
molecule converge       # deploy only
molecule verify         # verify only
```

### `docker` (Arch Linux container with systemd)

Runs in an `arch-systemd` Docker container. The `prepare.yml` installs `lightdm` via pacman and creates fixture config files under `/tmp/dotfiles`. No pre-existing installation required.

```bash
cd ansible/roles/lightdm
molecule test -s docker
molecule converge -s docker
molecule verify   -s docker
```

The docker scenario sets `lightdm_enable_service: false` because no display server is available in a headless container. The verify step confirms the service is **enabled** (systemd unit registered) but not **running** — which is the expected and correct state.

### What verify checks

- `lightdm` package is installed
- `/etc/lightdm/lightdm.conf.d/` directory exists
- `10-config.conf` — exists, owner root:root, mode 0644, contains `[Seat:*]`, `greeter-session=`, `display-setup-script=`, and references `add-and-set-resolution.sh`
- `add-and-set-resolution.sh` — exists, mode 0755, owner lightdm:lightdm, has `#!/bin/bash` shebang, uses `xrandr`, contains `exit 0`
- `lightdm.service` is enabled (when `lightdm_enable_service: true`)
- Service not running in headless environment is expected and logged

## Known bugs fixed

### `source_stat` variable scoping bug

Early versions of this role used a variable named `source_stat` that conflicted with the parent playbook scope when multiple roles registered the same variable name. The variable was renamed to `lightdm_source_stat` (role-prefixed) so each role's stat result is isolated. Always use role-prefixed variable names for `register:` to avoid cross-role pollution.
