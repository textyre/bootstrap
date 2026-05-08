# docker

Configures Docker daemon with CIS-hardened defaults (daemon.json, service management, user group membership).

## Execution flow

`tasks/main.yml` is the role entrypoint and responsibility map. It has three layers:

1. **Core** (`tasks/core.yml`) -- validates the public role contract, loads `vars/<os_family>.yml`, and includes `tasks/validate.yml`. It does not mutate the host.
2. **Apply** (`tasks/apply.yml`) -- applies the validated contract: storage prerequisites, daemon config, group membership, service state, and pending handlers.
3. **Verify** (`tasks/verify.yml`) -- observes the applied implementation: `daemon.json` exists/parses and the running daemon reports the configured storage driver.
4. **Report** -- writes execution report via `common/report_phase` + `report_render`.

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `Restart docker` | `daemon.json` change | Restarts Docker service via `ansible.builtin.service`. Skipped when `docker_enable_service: false`. |

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
| `docker_storage_driver` | `"overlay2"` | careful | Explicit Docker storage driver. Empty values and Docker auto-selection are rejected. Supported: `overlay2`, `btrfs`, `zfs`, `fuse-overlayfs`. Changing on existing installs may require data migration |
| `docker_storage_supported_drivers` | `["overlay2", "btrfs", "zfs", "fuse-overlayfs"]` | internal | Allow-list used by validation, preflight, and tests |
| `docker_userns_remap` | `"default"` | careful | User namespace remapping. Isolates container UIDs from host. Breaks bind-mount permissions -- use named volumes or `chown 100000:100000` |
| `docker_icc` | `false` | careful | Inter-container communication via `docker0` bridge. `false` = containers must use user-defined networks (Docker Compose creates them automatically) |
| `docker_live_restore` | `true` | safe | Keep containers running when dockerd restarts. Incompatible with Docker Swarm |
| `docker_no_new_privileges` | `true` | safe | Block setuid privilege escalation in containers. Per-container override: `--security-opt no-new-privileges=false` |
| `docker_daemon_overwrite` | `{}` | internal | Extra daemon.json settings not owned by dedicated `docker_*` variables. Managed keys such as `storage-driver`, `log-driver`, `userns-remap`, `icc`, `live-restore`, and `no-new-privileges` are rejected here |

### Storage driver contract

The role always writes `storage-driver` to `/etc/docker/daemon.json`. Operators must choose the driver through `docker_storage_driver`; `docker_daemon_overwrite.storage-driver` is rejected because storage driver ownership belongs to the role core, not to generic daemon extras.

Supported modern drivers:

| Driver | Preflight |
|--------|-----------|
| `overlay2` | Overlayfs is already registered, or the current kernel module tree exists and `modinfo overlay` / `modprobe overlay` can register it |
| `btrfs` | Docker data root, or its parent before first start, is mounted on `btrfs` |
| `zfs` | `zfs version` succeeds and Docker data root is mounted on `zfs` |
| `fuse-overlayfs` | `fuse-overlayfs --version` succeeds; the package must be prepared outside this role |

### CIS Docker Benchmark defaults

| Setting | Value | CIS Control | Effect |
|---------|-------|-------------|--------|
| `userns-remap` | `"default"` | CIS 2.8 | Isolates container UIDs from host UIDs |
| `icc` | `false` | CIS 2.1 | Disables direct inter-container communication on docker0 |
| `live-restore` | `true` | CIS 2.14 | Daemon resilience without stopping containers |
| `no-new-privileges` | `true` | CIS 5.25 | Prevents privilege escalation via setuid |

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

### Adding custom daemon.json settings

```yaml
# In host_vars/<hostname>/docker.yml:
docker_daemon_overwrite:
  dns:
    - "8.8.8.8"
    - "8.8.4.4"
  default-address-pools:
    - base: "172.80.0.0/16"
      size: 24
```

Values in `docker_daemon_overwrite` are merged recursively for daemon settings not managed by dedicated role variables. Managed keys are rejected during core validation.

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

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RedHat | Void Linux | Gentoo |
|--------|-----------|-----------------|-----------------|------------|--------|
| Service name | `docker` | `docker` | `docker` | `docker` | `docker` |
| Config path | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` |
| Package | `docker` | `docker.io` / `docker-ce` | `docker-ce` | `docker` | `app-containers/docker` |

Docker service name is consistent across all distros. Config path is always `/etc/docker/daemon.json`. Package installation is handled outside this role.

## Logs

### Log files

| Source | Path | Contents | Rotation |
|--------|------|----------|----------|
| Docker daemon | `journalctl -u docker` | Daemon start/stop, config reload, container lifecycle | System journal rotation |
| Container logs (journald) | `journalctl CONTAINER_NAME=<name>` | Container stdout/stderr | System journal rotation |
| Container logs (json-file) | `/var/lib/docker/containers/<id>/<id>-json.log` | Container stdout/stderr | `docker_log_max_size` / `docker_log_max_file` |
| daemon.json | `/etc/docker/daemon.json` | Static config file (not a log) | N/A -- managed by this role |

### Reading the logs

- Daemon errors: `journalctl -u docker -n 50 --no-pager`
- Container logs: `docker logs <container>` or `journalctl CONTAINER_NAME=<name>`
- Config validation: `python3 -m json.tool /etc/docker/daemon.json`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in supported list | Check `ansible_facts['os_family']` matches one of: Archlinux, Debian, RedHat, Void, Gentoo |
| Role fails at "Assert target user exists" | `docker_user` resolves to a non-existent user | Set `docker_user` to a valid username or ensure the user is created before this role |
| daemon.json validation fails | Invalid JSON in template output | Check `docker_daemon_overwrite` for syntax errors. Run: `python3 -m json.tool /etc/docker/daemon.json` |
| Role fails at "Assert Docker storage driver is explicit and supported" | Empty, legacy, or misspelled storage driver | Set `docker_storage_driver` to one of: `overlay2`, `btrfs`, `zfs`, `fuse-overlayfs` |
| Role fails during storage preflight | Selected driver prerequisites are missing | Fix the package/filesystem/kernel prerequisite shown in the failure before starting Docker |
| Docker won't start after config change | Invalid daemon.json options or existing Docker data created with another driver | `journalctl -u docker -n 50` for error. Storage-driver changes on an existing `/var/lib/docker` may require data migration |
| userns-remap breaks volume permissions | Container UID remapped to 100000+ range | Use named volumes, or `chown 100000:100000 /path/to/bind/mount` on host |
| Containers can't communicate | `docker_icc: false` blocks docker0 bridge traffic | Use user-defined networks (`docker network create`) or Docker Compose networks (created automatically) |
| Handler doesn't restart Docker | `docker_enable_service: false` prevents restart | Set `docker_enable_service: true` or restart manually: `systemctl restart docker` |

## Testing

Run project checks from the VM through the Taskfile. `task --yes test-docker` runs the Docker role Molecule default contract through the same environment as the workstation playbooks: syntax, converge, idempotence, and verify.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Default / Taskfile | `task --yes test-docker` | Required role gate | Local VM run, explicit storage config, invalid driver rejection, daemon JSON validation, idempotence, service/runtime verification |
| Docker scenario | `molecule test -s docker` | Container matrix feedback when a Taskfile target invokes it | Arch + Ubuntu containers, security enabled/disabled hosts, config and idempotence with service skipped |
| Vagrant scenario | `molecule test -s vagrant` | Full VM validation when a Taskfile target invokes it | Real systemd, real packages, Arch + Ubuntu matrix, service start, runtime driver match, process and named-volume smoke checks |

Scenario inventory should only describe scenario-specific choices. Role defaults remain the source of default expectations; `molecule/shared/verify.yml` loads the role defaults through `tasks/noop.yml` and asserts observable state instead of copying defaults into test variables.

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Runtime verify: `docker info` reports the selected storage driver, and the opt-in smoke check proves container execution and named volumes work
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Directories | `/etc/docker/` exists with root:root 0755 | TEST-008 |
| Config files | `daemon.json` exists, valid JSON, correct permissions | TEST-008 |
| Config content | log-driver, security keys match variables | TEST-008 |
| Negative paths | Security keys absent when features disabled | TEST-008 |
| User group | docker group exists, user membership | TEST-008 |
| Services | docker.service running + enabled (vagrant only) | TEST-008 |
| Runtime | `docker info` matches configured settings (vagrant only) | TEST-008 |
| Storage input contract | empty driver, legacy `vfs`, and managed daemon-key overrides are rejected before mutation in `molecule/shared/validate/` | TEST-011 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `daemon.json missing or wrong permissions` | Converge didn't run or failed silently | Run full sequence: `molecule test -s docker`, not just converge |
| `JSON validation failed` | Template produces invalid JSON | Check values passed through `docker_daemon_overwrite` |
| Idempotence failure on daemon.json | Rendered daemon.json changed between runs | Compare the rendered file content; the template should be stable |
| `docker.service is not enabled` (vagrant) | Docker not installed in prepare step | Check `molecule/vagrant/prepare.yml` installs Docker |
| `User not in docker group` | User doesn't exist in container | Set `docker_add_user_to_group: false` in container host_vars |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `docker` | Entire role | Full apply: `ansible-playbook playbook.yml --tags docker` |
| `docker:configure` | daemon.json deployment + user group | Config-only: `ansible-playbook playbook.yml --tags docker:configure` |
| `docker:service` | Service enable/start only | Restart Docker without re-deploying config: `ansible-playbook playbook.yml --tags docker:service` |
| `security` | Security-tagged tasks (daemon.json deploy) | Audit security configuration |
| `report` | Logging/report tasks only | Re-generate execution report: `ansible-playbook playbook.yml --tags report` |

```bash
# Full role apply
ansible-playbook playbook.yml --tags docker

# Config only, no service management
ansible-playbook playbook.yml --tags docker:configure

# Service management only
ansible-playbook playbook.yml --tags docker:service
```

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
| `tasks/main.yml` | Layer map: core, apply, verify, report | When changing role responsibility boundaries |
| `tasks/core.yml` | OS support, OS vars, and validation entrypoint | When changing the role core contract |
| `tasks/apply.yml` | Implementation dispatcher for daemon, group, service, handlers | When changing implementation flow |
| `tasks/validate.yml` | Role input validation and daemon key ownership | When changing public variable contract |
| `tasks/storage_preflight.yml` | Storage implementation prerequisite dispatcher | When adding/removing storage drivers |
| `tasks/storage_preflight_overlay2.yml` | overlay2 prerequisite checks | When changing overlay2 support |
| `tasks/storage_preflight_btrfs.yml` | btrfs prerequisite checks | When changing btrfs support |
| `tasks/storage_preflight_zfs.yml` | zfs prerequisite checks | When changing zfs support |
| `tasks/storage_preflight_fuse_overlayfs.yml` | fuse-overlayfs prerequisite checks | When changing rootless/fuse support |
| `tasks/configure_daemon.yml` | daemon.json directory and template deployment | When changing daemon configuration |
| `tasks/user_group.yml` | docker group and user membership | When changing group contract |
| `tasks/service.yml` | Docker service state | When changing service behavior |
| `tasks/verify.yml` | In-role implementation verification dispatcher | When adding/removing role verification categories |
| `tasks/verify_daemon.yml` | daemon.json and permissions verification | When changing daemon file contract |
| `tasks/verify_runtime.yml` | `docker info` storage-driver verification | When changing runtime contract |
| `tasks/noop.yml` | Empty task for molecule defaults loading | Never |
| `handlers/main.yml` | Service restart handler | Rarely |
| `meta/main.yml` | Galaxy metadata | When changing role metadata |
| `molecule/shared/converge.yml` | Shared apply + input validation playbook | When changing role application shape |
| `molecule/shared/validate/*.yml` | Negative input-contract tests | When changing validation behavior |
| `molecule/shared/verify.yml` | Verify dispatcher that loads role defaults and checks observable state | When changing test categories |
| `molecule/shared/verify/*.yml` | Focused Molecule contract checks | When changing test assertions |
| `molecule/docker/` | Docker-based test scenario | When changing container test config |
| `molecule/vagrant/` | Vagrant-based test scenario | When changing VM test config |
| `molecule/default/` | Localhost test scenario | When changing local test config |
