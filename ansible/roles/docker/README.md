# docker

Configures Docker daemon with CIS-hardened defaults (daemon.json, service management, user group membership).

## Execution flow

1. **Preflight** (`tasks/main.yml`) -- asserts OS family is in the supported list (`Archlinux`, `Debian`, `RedHat`, `Void`, `Gentoo`); fails immediately if unsupported
2. **Load OS variables** (`vars/<os_family>.yml`) -- loads distro-specific service name (`_docker_service_name`)
3. **Create config directory** -- ensures `/etc/docker/` exists with `root:root 0755`
4. **Build daemon config** -- assembles `docker_daemon_config` dict via `set_fact`, conditionally merging security settings (`userns-remap`, `icc`, `live-restore`, `no-new-privileges`) and storage driver
5. **Deploy daemon.json** -- renders `/etc/docker/daemon.json` from Jinja2 template with JSON validation (`python3 -m json.tool`). **Triggers handler:** if config changed, Docker will be restarted.
6. **User group** -- ensures `docker` group exists and adds `docker_user` to it (skipped when `docker_add_user_to_group: false`)
7. **Service** -- enables and starts Docker service (skipped when `docker_enable_service: false`)
8. **Verify** (`tasks/verify.yml`) -- checks `/etc/docker/` permissions, `daemon.json` validity (JSON parse), correct ownership and mode
9. **Report** -- writes execution report via `common/report_phase` + `report_render`

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `Restart docker` | Config file change (step 5) | Restarts Docker service via `ansible.builtin.service`. Skipped when `docker_enable_service: false`. |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `docker_user` | `SUDO_USER` or `user_id` | safe | User to add to the `docker` group. Detected automatically from the invoking user |
| `docker_add_user_to_group` | `true` | careful | Add `docker_user` to `docker` group. Equivalent to root access -- only enable for trusted users |
| `docker_enable_service` | `true` | safe | Enable and start the Docker service. Set `false` for config-only runs or container testing |
| `docker_log_driver` | `"journald"` | safe | Container logging driver. Common values: `journald`, `json-file`, `syslog` |
| `docker_log_max_size` | `"10m"` | safe | Max log file size per container (only applies to `json-file` and `local` drivers) |
| `docker_log_max_file` | `"3"` | safe | Max number of rotated log files per container (only applies to `json-file` and `local` drivers) |
| `docker_storage_driver` | `""` | careful | Storage driver override. Empty = Docker auto-selects (usually `overlay2`). Changing on existing installs may require data migration |
| `docker_userns_remap` | `"default"` | careful | User namespace remapping. Isolates container UIDs from host. Breaks bind-mount permissions -- use named volumes or `chown 100000:100000` |
| `docker_icc` | `false` | careful | Inter-container communication via `docker0` bridge. `false` = containers must use user-defined networks (Docker Compose creates them automatically) |
| `docker_live_restore` | `true` | safe | Keep containers running when dockerd restarts. Incompatible with Docker Swarm |
| `docker_no_new_privileges` | `true` | safe | Block setuid privilege escalation in containers. Per-container override: `--security-opt no-new-privileges=false` |

### Internal mappings (`vars/`)

These files contain cross-platform mappings. Do not override via inventory -- edit the files directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | Service name for Arch Linux (`docker`) | Adding Arch-specific overrides |
| `vars/debian.yml` | Service name for Debian/Ubuntu (`docker`) | Adding Debian-specific overrides |
| `vars/redhat.yml` | Service name for Fedora/RHEL (`docker`) | Adding RedHat-specific overrides |
| `vars/void.yml` | Service name for Void Linux (`docker`) | Adding Void-specific overrides |
| `vars/gentoo.yml` | Service name for Gentoo (`docker`) | Adding Gentoo-specific overrides |

## Examples

### Changing the log driver

```yaml
# In group_vars/all/docker.yml or host_vars/<hostname>/docker.yml:
docker_log_driver: "json-file"
docker_log_max_size: "50m"
docker_log_max_file: "5"
```

- `journald` (default) -- logs go to systemd journal, searchable via `journalctl CONTAINER_NAME=...`
- `json-file` -- logs stored as JSON files in `/var/lib/docker/containers/<id>/`, rotated by `max-size`/`max-file`

### Disabling security hardening for development

```yaml
# In host_vars/<dev-workstation>/docker.yml:
docker_userns_remap: ""          # disable user namespace remapping
docker_icc: true                 # allow inter-container communication
docker_no_new_privileges: false  # allow setuid in containers
```

### Skipping user group membership

```yaml
# In host_vars/<hostname>/docker.yml:
docker_add_user_to_group: false
```

Docker commands will require `sudo`. Safer for shared or production-like machines.

### Config-only run (no service management)

```yaml
# In host_vars/<hostname>/docker.yml:
docker_enable_service: false
```

Or use tags: `ansible-playbook playbook.yml --tags docker:configure`

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Service name | `docker` | `docker` | `docker` | `docker` | `docker` |
| Package name | `docker` | `docker.io` | `docker` | `docker` | `app-containers/docker` |
| Config path | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` |

The config path is identical across all distros. Package names differ -- this role does not install Docker, so the package name is only relevant to the prepare step in molecule tests.

## Logs

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| Container logs (journald) | `journalctl CONTAINER_NAME=<name>` | Container stdout/stderr | System journal rotation |
| Container logs (json-file) | `/var/lib/docker/containers/<id>/<id>-json.log` | Container stdout/stderr as JSON | `docker_log_max_size` / `docker_log_max_file` |
| Docker daemon | `journalctl -u docker` | Daemon start/stop, errors, warnings | System journal rotation |
| daemon.json | `/etc/docker/daemon.json` | Not a log -- config file deployed by this role | N/A |

### Reading the logs

- Daemon issues: `journalctl -u docker -n 50 --no-pager`
- Container logs: `docker logs <container>` or `journalctl CONTAINER_NAME=<name>`
- Live-restore events: `journalctl -u docker | grep live-restore`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in supported list | Check `ansible_facts['os_family']` -- must be one of: Archlinux, Debian, RedHat, Void, Gentoo |
| `daemon.json` validation fails | Invalid JSON syntax in merged config | Run `python3 -m json.tool /etc/docker/daemon.json` to see the error. Check variable values for unquoted strings |
| Docker won't start after config change | Bad daemon.json or conflicting settings | `journalctl -u docker -n 50`. Common: `userns-remap` with incompatible storage driver |
| Containers can't talk to each other | `docker_icc: false` blocks `docker0` traffic | Use user-defined networks (`docker network create mynet`) or set `docker_icc: true` |
| Bind-mount permission denied | `userns-remap` shifts UIDs by 100000 | Use named volumes, or `chown 100000:100000` on host directories, or disable `docker_userns_remap: ""` |
| User can't run `docker` commands | Not in docker group, or session not refreshed | Check: `id -nG <user>`. If `docker` missing: verify `docker_add_user_to_group: true`. Log out and back in for group changes to take effect |
| Handler didn't restart Docker | `docker_enable_service: false` skips handler | Set `docker_enable_service: true` or restart manually: `systemctl restart docker` |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Config deployment, idempotence, daemon.json content, negative-path assertions |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic, services, or security settings | Real systemd, real packages, Arch + Ubuntu matrix, service state, runtime `docker info` |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Directory | `/etc/docker/` exists with `root:root 0755` | TEST-008 |
| Config file | `daemon.json` exists with `root:root 0644`, valid JSON | TEST-008 |
| Config content | `log-driver`, `log-opts`, security keys match variables | TEST-008 |
| Group | `docker` group exists, user is member | TEST-008 |
| Service | `docker.service` enabled + running (vagrant only) | TEST-008 |
| Runtime | `docker info` matches configured log driver, security options (vagrant only) | TEST-008 |
| Negative path | Security keys absent when features disabled, user NOT in group when disabled | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `docker package not found` | Package not installed in prepare step | Check `molecule/docker/prepare.yml` installs `docker` (Arch) or `docker.io` (Ubuntu) |
| Idempotence failure on daemon.json | Template produces different output on second run | Check `set_fact` for non-deterministic values |
| `python3 -m json.tool` validation fails | daemon.json template error | Run converge, then `docker exec <container> python3 -m json.tool /etc/docker/daemon.json` |
| Assertion failed: `icc` key absent | `docker_icc` host_var doesn't match expected path | Check `molecule.yml` host_vars match the assertion (nosec vs systemd platform) |
| Vagrant: `Python not found` | prepare.yml missing or bootstrap skipped | Check `prepare.yml` imports `shared/prepare-vagrant.yml` (TEST-009) |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `docker` | Entire role | Full apply: `ansible-playbook playbook.yml --tags docker` |
| `docker:configure` | daemon.json deployment + user group | Config-only: `ansible-playbook playbook.yml --tags docker:configure` |
| `docker:service` | Service enable/start only | Restart Docker without re-deploying config: `ansible-playbook playbook.yml --tags docker:service` |
| `report` | Logging/report tasks only | Re-generate execution report: `ansible-playbook playbook.yml --tags report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings and supported OS list | No -- override via inventory |
| `vars/archlinux.yml` | Service name for Arch Linux | Only when adding Arch-specific overrides |
| `vars/debian.yml` | Service name for Debian/Ubuntu | Only when adding Debian-specific overrides |
| `vars/redhat.yml` | Service name for Fedora/RHEL | Only when adding RedHat-specific overrides |
| `vars/void.yml` | Service name for Void Linux | Only when adding Void-specific overrides |
| `vars/gentoo.yml` | Service name for Gentoo | Only when adding Gentoo-specific overrides |
| `templates/daemon.json.j2` | Docker daemon config template | When changing config output format |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `tasks/noop.yml` | Empty task for molecule defaults loading | Never |
| `handlers/main.yml` | Service restart handler | Rarely |
| `meta/main.yml` | Galaxy metadata | When changing role metadata |
| `molecule/` | Test scenarios (docker, vagrant, default) | When changing test coverage |
