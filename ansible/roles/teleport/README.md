# teleport

Installs and configures a Teleport node agent for zero-trust SSH access with certificate authority integration.

## Execution flow

1. **Assert OS** — fails immediately if `ansible_facts['os_family']` is not in the supported list (Archlinux, Debian, RedHat, Void, Gentoo)
2. **Load OS variables** — includes `vars/<os_family>.yml` (package names, service names)
3. **Assert auth server** — fails if `teleport_auth_server` is empty
4. **Validate join config** (`tasks/join.yml`) — validates join token configuration
5. **Install** (`tasks/install.yml`, when `teleport_manage_install: true`) — installs Teleport via package manager (Arch), official APT/YUM repo (Debian/RedHat), or binary CDN download (Void/Gentoo). Binary path: version-checks existing install, downloads only if needed, deploys systemd unit file if `service_mgr == systemd`. **Triggers handler:** daemon-reload if unit file changes.
6. **Configure** (`tasks/configure.yml`, when `teleport_manage_config: true`) — creates `/var/lib/teleport` (0750), deploys `/etc/teleport.yaml` (0600, no_log). **Triggers handler:** "Restart teleport" if config changes.
7. **CA export** (`tasks/ca_export.yml`, when `teleport_export_ca_key: true`) — reads Teleport user CA from auth server via `tctl auth export`, writes to `teleport_ca_keys_file`, sets `ssh_teleport_integration: true` fact for the `ssh` role.
8. **Service** (when `teleport_manage_service: true`) — enables and starts `teleport` service via `ansible.builtin.service` (init-system agnostic).
9. **Verify** (`tasks/verify.yml`) — checks binary responds to `teleport version`, config file exists with mode 0600, reports service status (does not assert running state — requires live cluster).
10. **Report** — writes execution summary via `common/report_phase.yml` and `common/report_render.yml`.

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|--------------|
| `restart teleport` | Config file change (step 6) | Restarts teleport service via `ansible.builtin.service`. |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `teleport_enabled` | `true` | safe | Set `false` to skip the entire role |
| `teleport_manage_install` | `true` | safe | Set `false` to skip installation (useful if Teleport is pre-installed) |
| `teleport_manage_config` | `true` | safe | Set `false` to skip config deployment (manage config separately) |
| `teleport_manage_service` | `true` | safe | Set `false` to skip service enable/start |
| `teleport_version` | `"17.4.10"` | careful | Full semver string. Used for binary downloads and major version for package repos. Must match an available release. |
| `teleport_auth_server` | `""` | careful | **Required.** Auth/proxy server address, e.g. `auth.example.com:443`. Role fails if empty. |
| `teleport_join_token` | `""` | careful | **Required.** Join token for cluster registration. |
| `teleport_node_name` | `{{ ansible_hostname }}` | safe | Node name shown in the Teleport UI |
| `teleport_labels` | `{}` | safe | Key-value map of node labels for RBAC role assignment |
| `teleport_ssh_enabled` | `true` | careful | Enable the SSH service on this node. Set `false` for proxy-only nodes. |
| `teleport_proxy_mode` | `false` | careful | Run as a proxy node. Changes the role of this node in the cluster. |
| `teleport_session_recording` | `"node"` | careful | Session recording location: `node`, `proxy`, or `off`. Affects where session data is stored. |
| `teleport_enhanced_recording` | `false` | internal | BPF-based enhanced session recording. Requires Linux kernel ≥ 5.8 with BTF enabled. Breaking change if kernel doesn't support it. |
| `teleport_export_ca_key` | `true` | safe | Export Teleport user CA and configure `ssh` role integration |
| `teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | careful | Destination path for the exported CA public key. Must match `TrustedUserCAKeys` in `sshd_config`. |
| `teleport_config_overwrite` | `{}` | careful | Dict merged on top of the rendered `teleport.yaml`. Allows injecting arbitrary keys without modifying the template. |

### Internal mappings (`vars/`)

These files contain cross-platform mappings. Do not override via inventory — edit directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | Service name map per init system (`teleport` for all) | Adding a new init system |
| `vars/archlinux.yml` | Package list: `teleport-bin` (AUR) | Changing the AUR package name |
| `vars/debian.yml` | Package list: empty (repo method installs directly) | If Debian switches to a package-based install |
| `vars/redhat.yml` | Package list: mirrors Debian pattern | Same as Debian |
| `vars/void.yml` | Package list: empty (binary method) | If Void gets an official package |
| `vars/gentoo.yml` | Package list: empty (binary method) | If Gentoo gets an official package |

## Examples

### Minimal required configuration

```yaml
# In host_vars/<hostname>/teleport.yml:
teleport_auth_server: "auth.example.com:443"
teleport_join_token: "{{ vault_teleport_join_token }}"
```

### With labels and proxy-mode recording

```yaml
# In group_vars/workstations/teleport.yml:
teleport_auth_server: "auth.example.com:443"
teleport_join_token: "{{ vault_teleport_join_token }}"
teleport_labels:
  env: production
  role: workstation
teleport_session_recording: "proxy"
teleport_enhanced_recording: true
```

- `teleport_session_recording: "proxy"` — session data stored at the proxy instead of the node. Reduces node disk usage.
- `teleport_enhanced_recording: true` — BPF-based recording. Requires kernel ≥ 5.8 with BTF. Do not enable on older kernels.

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/teleport.yml:
teleport_enabled: false
```

### Injecting extra teleport.yaml keys without modifying the template

```yaml
# In host_vars/<hostname>/teleport.yml:
teleport_config_overwrite:
  teleport:
    diag_addr: "0.0.0.0:3000"
```

### Skip CA export (when not using the ssh role)

```yaml
# In group_vars/all/teleport.yml:
teleport_export_ca_key: false
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Install method | `package` (AUR) | `repo` (APT) | `repo` (YUM) | `binary` (CDN) | `binary` (CDN) |
| Package name | `teleport-bin` | `teleport` | `teleport` | — | — |
| Binary path (binary method) | — | — | — | `/usr/local/bin/teleport` | `/usr/local/bin/teleport` |
| Config path | `/etc/teleport.yaml` | `/etc/teleport.yaml` | `/etc/teleport.yaml` | `/etc/teleport.yaml` | `/etc/teleport.yaml` |
| Data directory | `/var/lib/teleport` | `/var/lib/teleport` | `/var/lib/teleport` | `/var/lib/teleport` | `/var/lib/teleport` |
| Service name | `teleport` | `teleport` | `teleport` | `teleport` | `teleport` |
| Systemd unit | package-provided | package-provided | package-provided | deployed by role | deployed by role |

## Logs

### Log sources

| Source | How to access | Contents |
|--------|--------------|---------- |
| Service output | `journalctl -u teleport -f` | Cluster join attempts, SSH session events, auth failures, config errors |
| Session recordings | `/var/lib/teleport/log/` | BPF or PTY session recording data (local node recording only) |
| Diagnostics endpoint | `http://localhost:3000/metrics` | Prometheus metrics (when `teleport_config_overwrite.teleport.diag_addr` is set) |

Teleport does not write standalone log files by default — all output goes to the system journal. There is no built-in log rotation configuration; journal rotation applies.

### Reading the logs

- **Failed to join cluster:** `journalctl -u teleport -n 100 | grep -i "error\|failed\|join"` — look for TLS errors, token expiry, or unreachable auth server.
- **Service won't start:** `journalctl -u teleport -n 50` — usually a config syntax error or missing `auth_server`.
- **Check config parsed correctly:** `teleport configure check --config /etc/teleport.yaml`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert auth server is configured" | `teleport_auth_server` is empty or not set | Set `teleport_auth_server: "auth.example.com:443"` in inventory |
| `teleport.service` fails to start | `journalctl -u teleport -n 50` | Usually wrong `auth_server` address or expired `join_token`. Verify cluster is reachable: `curl -k https://<auth_server>/webapi/ping` |
| Service starts but immediately exits | `journalctl -u teleport -n 100 \| grep error` | TLS certificate errors: clock skew > 5 min causes TLS rejection. Run `chronyc tracking`. Also check firewall allows outbound to auth server port. |
| `/etc/teleport.yaml` has wrong permissions | `stat /etc/teleport.yaml` | Role sets 0600 on deploy. If permissions changed externally: re-run with `--tags teleport` |
| CA export fails | `journalctl -u teleport -n 30` | CA export requires a running auth server with `tctl` access. Set `teleport_export_ca_key: false` for nodes without cluster access. |
| AUR package install fails on Arch | Check `ansible output` for pacman errors | `teleport-bin` is an AUR package — requires an AUR helper. Install via binary method: `teleport_install_method: binary` in host_vars. |
| Idempotence failure on config deploy | `molecule converge` runs twice and shows `changed` | A Jinja2 expression in `templates/teleport.yaml.j2` produces non-deterministic output. Check for filters that change on each run. |

## Testing

Two scenarios are required for every role. Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| `default` (localhost) | `molecule test -s default` | Smoke test: after changing templates or variables | Syntax, variable loading, config rendered with correct content and 0600 permissions |
| `docker` | `molecule test -s docker` | After changing task logic, service management, or install paths | Package install, service enabled, idempotence, Arch + Ubuntu matrix |
| `vagrant` | `molecule test -s vagrant` | After changing OS-specific logic or before releasing | Real systemd, real packages, Arch + Ubuntu multi-distro validation |

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all `ansible.builtin.assert` tasks pass
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Binary | `teleport` in PATH, `teleport version` exits 0 | TEST-008 |
| Config file | `/etc/teleport.yaml` exists, mode 0600, owned root | TEST-008 |
| Config content | schema `v3`, correct node name, auth server, session recording mode | TEST-008 |
| Data directory | `/var/lib/teleport` exists, mode 0750 | TEST-008 |
| Systemd unit | `teleport.service` present, mode 0644, enabled (systemd only) | TEST-008 |
| Skip path | `teleport_enabled: false` runs without error and installs nothing | TEST-011 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `which: no teleport in PATH` | Binary install failed silently | Check `teleport_install_method` for the platform; check CDN URL is reachable in Docker |
| Idempotence failure: `/etc/teleport.yaml` changed | Non-deterministic template output | Check `teleport.yaml.j2` for filters that change on each run; `no_log: true` on task hides diff |
| `Assert /etc/teleport.yaml exists` fails | `teleport_manage_config: false` was set in converge | Remove the override or check converge vars match what verify expects |
| `Assert teleport.service unit file exists` fails | Non-systemd container, or binary not deployed | Unit file section is guarded by `service_mgr == systemd`; check if container actually uses systemd |
| Vagrant: `Python not found` | `prepare.yml` platform dispatch failed | Check `prepare_archlinux.yml` and `prepare_debian.yml` exist and `ansible_facts['os_family']` resolves |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `teleport` | Entire role | Full apply: `ansible-playbook workstation.yml --tags teleport` |
| `teleport,install` | Installation only | Upgrade Teleport binary without touching config: `ansible-playbook workstation.yml --tags teleport,install` |
| `teleport,security` | Join token validation + CA export | Re-export CA after cluster rotation: `ansible-playbook workstation.yml --tags teleport,security` |
| `teleport,service` | Service enable/start only | Restart service without re-deploying config: `ansible-playbook workstation.yml --tags teleport,service` |
| `teleport,report` | Execution report only | Re-generate report in CI: `ansible-playbook workstation.yml --tags teleport,report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No — override via inventory |
| `vars/main.yml` | Service name map per init system | Only when adding init system support |
| `vars/<os_family>.yml` | Package names per distro family | Only when adding distro support |
| `templates/teleport.yaml.j2` | Teleport config template (v3 format) | When changing config structure |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/install.yml` | Install Teleport (package/repo/binary) | When changing install logic |
| `tasks/configure.yml` | Deploy `/etc/teleport.yaml` | When changing config deploy logic |
| `tasks/ca_export.yml` | Export CA key + set ssh integration fact | When changing CA export behavior |
| `tasks/join.yml` | Validate join token configuration | When changing join validation |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `handlers/main.yml` | Service restart handler | Rarely |
| `molecule/default/` | Localhost smoke test scenario | When changing smoke test coverage |
| `molecule/docker/` | Docker containerized test scenario | When changing Docker test coverage |
| `molecule/vagrant/` | Full VM test scenario | When changing multi-distro coverage |
| `molecule/shared/converge.yml` | Shared converge playbook (all scenarios) | When changing test variables or adding edge cases |
| `molecule/shared/verify.yml` | Shared verify playbook (all scenarios) | When adding verification assertions |
| `requirements.yml` | Role dependency declaration (common role) | When adding role dependencies |
| `meta/main.yml` | Role metadata | Rarely |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
