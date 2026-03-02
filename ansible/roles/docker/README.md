# docker

Docker daemon configuration with CIS-hardened defaults (daemon.json, service, user group).

## What this role does

- [x] Creates `/etc/docker/` directory with correct ownership (root:root 0755)
- [x] Builds `docker_daemon_config` dict via `set_fact` (conditionally merges security settings)
- [x] Deploys `/etc/docker/daemon.json` from Jinja2 template with JSON validation (`python3 -m json.tool`)
- [x] Ensures `docker` group exists and adds the target user to it
- [x] Enables and starts the `docker` service (skippable via `docker_enable_service: false`)
- [x] Restarts Docker on config change via handler

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `docker_user` | `SUDO_USER` → `user_id` | User to add to the `docker` group |
| `docker_add_user_to_group` | `true` | Whether to add the user to `docker` group |
| `docker_enable_service` | `true` | Enable and start the Docker service |
| `docker_log_driver` | `"journald"` | Logging driver for containers |
| `docker_log_max_size` | `"10m"` | Max log file size (non-journald drivers) |
| `docker_log_max_file` | `"3"` | Max number of log files (non-journald drivers) |
| `docker_storage_driver` | `""` | Storage driver (empty = use Docker default) |
| `docker_userns_remap` | `"default"` | User namespace remapping (CIS: isolates container UIDs from host) |
| `docker_icc` | `false` | Inter-container communication via docker0 (CIS: disable) |
| `docker_live_restore` | `true` | Keep containers running when dockerd restarts |
| `docker_no_new_privileges` | `true` | Block setuid privilege escalation in containers |

## Security defaults

All security variables ship with CIS Docker Benchmark values enabled:

| Setting | Value | CIS Control |
|---------|-------|-------------|
| `userns-remap` | `"default"` | Isolates container UIDs from host UIDs |
| `icc` | `false` | Disables direct inter-container communication |
| `live-restore` | `true` | Daemon resilience without stopping containers |
| `no-new-privileges` | `true` | Prevents privilege escalation via setuid |

> **Note on userns-remap:** Requires `CONFIG_USER_NS=y` kernel support (enabled on Arch and Ubuntu 24.04).
> Volume permissions: use named volumes or `chown 100000:100000` on host bind-mount directories.

## Tags

`docker`, `docker:configure` (daemon.json + group), `docker:service` (enable/start only)

Use `--skip-tags service` or set `docker_enable_service: false` to skip service management
(e.g., in container-based molecule scenarios).

## Molecule test coverage

The `docker` scenario tests four platform configurations:
- `Archlinux-systemd` / `Ubuntu-systemd` — default security settings (all CIS features enabled)
- `Archlinux-nosec` / `Ubuntu-nosec` — all optional security settings disabled (tests key-absent paths)

## Molecule scenarios

| Scenario | Driver | Scope | Notes |
|----------|--------|-------|-------|
| `default` | localhost | Config + service | Runs against real machine, requires vault |
| `docker` | Docker | Config-only | Uses DinD container, skips service start |
| `vagrant` | Vagrant (libvirt) | Full | Real VMs with running daemon, Arch + Ubuntu |

## Prerequisites

Docker must be installed before running this role. The role only configures Docker — it does not install the package. Use your distro's package manager or a dedicated installation role before this one.

## Supported platforms

| Platform | Status |
|----------|--------|
| Arch Linux | Primary, fully tested |
| Ubuntu 24.04 | Tested via molecule (docker + vagrant scenarios) |
| Fedora / RHEL | Supported (distro-agnostic tasks), community tested |
| Void Linux | Supported (distro-agnostic tasks), community tested |
| Gentoo | Supported (distro-agnostic tasks), community tested |
