# docker

Configures an installed Docker Engine for secure workstation use.

The role owns Docker daemon settings and service state. Docker package installation remains owned by the project package layer. User access to the root-equivalent Docker socket is not granted by this role; administrators use Docker through `sudo`.

## Execution flow

1. **Validate** (`tasks/validate.yml`) checks the supported OS, storage driver, and ownership of daemon settings.
2. **Configure** (`tasks/configure/`) validates and deploys `/etc/docker/daemon.json`.
3. **Service** (`tasks/service.yml`) enables and starts Docker, or restarts it when daemon configuration changed.
4. **Report** (`tasks/main.yml`) renders the execution report through the `common` role.

### Handlers

The role has no handlers. A changed daemon configuration is applied immediately in the service phase.

## Variables

### Configurable (`defaults/main.yml`)

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `docker_manage_daemon` | `true` | careful | Own and deploy `/etc/docker/daemon.json`. |
| `docker_log_driver` | `journald` on systemd, otherwise `local` | safe | Default container log destination. |
| `docker_log_max_size` | `10m` | safe | Per-container log rotation size for drivers supporting `log-opts`. |
| `docker_log_max_file` | `3` | safe | Number of rotated container logs retained. |
| `docker_storage_driver` | `overlay2` | careful | Storage backend: `overlay2`, `btrfs`, `zfs`, or `fuse-overlayfs`. Changing it with existing data requires migration. |
| `docker_userns_remap` | `default` | careful | Maps container root away from host root. Writable bind mounts may need ownership changes; named volumes are preferred. |
| `docker_icc` | `true` | careful | Allows communication between containers on the same Docker network. Use separate user-defined networks to isolate workloads. |
| `docker_live_restore` | `true` | safe | Keeps containers alive while dockerd restarts. |
| `docker_no_new_privileges` | `true` | safe | Prevents privilege acquisition through setuid binaries by default. |
| `docker_daemon_extra` | `{}` | careful | Additional daemon keys not already owned by dedicated variables. Managed-key conflicts are rejected. |

### User namespace remapping

With `docker_userns_remap: default`, Docker creates the `dockremap` user and maps
container UID/GID ranges through `/etc/subuid` and `/etc/subgid`. The host kernel
must support user namespaces. After the first successful daemon start, both files
must contain non-overlapping ranges for `dockremap`; some distributions do not add
those ranges automatically. See the
[Docker user namespace documentation](https://docs.docker.com/engine/security/userns-remap/).

Enable remapping before creating production images, containers, and volumes.
Changing it on an existing Docker data root makes previously created Docker objects
unavailable under the new mapping until the old configuration is restored. Writable
bind mounts require ownership compatible with the remapped host IDs.

Daemon-wide remapping is incompatible with host PID/network namespaces, some external
volume or storage drivers, and privileged containers unless the individual container
uses `--userns=host` and accepts the resulting isolation trade-off.

### Internal mappings (`vars/main.yml`)

`vars/main.yml` contains the five supported OS families, the stable service name, the accepted storage drivers, and the daemon keys owned by dedicated variables. These are implementation constants, not inventory settings.

## Examples

### Configure the Docker service

```yaml
# ansible/inventory/group_vars/all/system.yml
docker_storage_driver: overlay2
```

Run administrative Docker commands through `sudo`, for example `sudo docker ps`. The role does not add users to the root-equivalent `docker` group and therefore does not bypass the project's sudo password and audit policy.

### Add daemon settings

```yaml
# ansible/inventory/group_vars/all/system.yml
docker_daemon_extra:
  dns:
    - "8.8.8.8"
  default-address-pools:
    - base: "172.80.0.0/16"
      size: 24
```

Dedicated settings such as `storage-driver`, `log-driver`, `icc`, and `userns-remap` must use their `docker_*` variables instead.

## Cross-platform details

The role supports Arch Linux, Ubuntu/Debian, Fedora/RedHat, Void Linux, and Gentoo. All use `/etc/docker/daemon.json` and service `docker`.

Package names differ and are intentionally handled by the package layer:

| OS family | Typical package |
|-----------|-----------------|
| Arch Linux | `docker` |
| Ubuntu / Debian | `docker.io` |
| Fedora / RedHat | Docker Engine package selected by repository policy |
| Void Linux | `docker` |
| Gentoo | `app-containers/docker` |

Systemd hosts default to `journald`; runit, openrc, s6, and dinit hosts default to Docker's `local` log driver. Service management uses the init-agnostic Ansible service module.

## Logs

| Configuration | Location |
|---------------|----------|
| Docker daemon on systemd | `journalctl -u docker` |
| Container logs with `journald` | `journalctl CONTAINER_NAME=<name>` |
| Container logs with `local` or `json-file` | Docker data root under `/var/lib/docker/containers/` |

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `dockerd` is missing during template validation | Docker Engine package was not installed by the package layer | Apply the package layer before this role |
| Docker fails after changing storage driver | Existing data belongs to another backend or the selected filesystem prerequisite is missing | Migrate or clear Docker data according to the selected driver's official procedure |
| Bind mount is not writable | `userns-remap` maps container root to an unprivileged host UID | Prefer a named volume or assign compatible ownership to the bind path |
| Docker fails on first start with `userns-remap: default` | User namespaces are unavailable, or `dockremap` has no valid subordinate UID/GID ranges | Check host user-namespace support and non-overlapping `dockremap` entries in `/etc/subuid` and `/etc/subgid` |
| Existing images or containers disappear after enabling remapping | Docker uses a remapped data namespace under `/var/lib/docker` | Restore the previous setting to access old objects, or migrate/recreate them before enabling remapping permanently |
| Docker CLI reports permission denied | The role intentionally does not grant access to the root-equivalent Docker socket | Run the administrative Docker command through `sudo` |
| Containers on the same network cannot communicate | `docker_icc` is false | Enable ICC or remove the override; isolate workloads with separate user-defined networks |

## Testing

Testing runs only through the project remote VM or CI workflow.

| Scenario | Coverage |
|----------|----------|
| `docker` | Full role converge and idempotence with systemd and Docker service in privileged Arch and Ubuntu containers |
| `vagrant` | Full role converge and idempotence with a real Docker service on Arch and Ubuntu |

Both scenarios execute the same role pipeline. Docker provides fast service and idempotence coverage with the host kernel; Vagrant provides the real VM boundary. Neither scenario runs workload containers or tests Docker Engine features owned by the upstream project.

## File map

| Path | Purpose |
|------|---------|
| `tasks/main.yml` | Pipeline orchestrator |
| `tasks/validate.yml` | Public contract validation |
| `tasks/configure/` | Docker daemon configuration |
| `tasks/service.yml` | immediate config application and desired service state |
| `vars/main.yml` | internal platform and driver constants |
| `molecule/shared/` | Shared full-role converge playbook |
