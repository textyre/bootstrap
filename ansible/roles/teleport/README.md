# teleport

Teleport SSH access platform agent — installs and configures a Teleport node for zero-trust SSH access with certificate authority integration.

## What this role does

- [x] Installs Teleport via package manager (Arch), official repository (Debian/RedHat), or binary download (Void/Gentoo)
- [x] Architecture-aware binary downloads: `x86_64` → `amd64`, `aarch64` → `arm64`
- [x] Validates `teleport_auth_server` and `teleport_join_token` before proceeding (fail-fast)
- [x] Deploys `/etc/teleport.yaml` (v3 format) with auth server address, join token, node name, and labels
- [x] Configures session recording mode (`node`, `proxy`, or `off`)
- [x] Optional BPF-based enhanced session recording
- [x] Exports Teleport user CA public key and sets the `ssh_teleport_integration` fact for the `ssh` role
- [x] Init-system agnostic service management (systemd, runit, openrc, s6, dinit)
- [x] Verifies Teleport binary version, config file permissions (0600), and service status

## Requirements

**Supported distributions** (enforced via `assert` at role entry):

| OS Family | Distros |
|-----------|---------|
| Archlinux | Arch Linux |
| Debian | Debian, Ubuntu |
| RedHat | Fedora, RHEL, CentOS |
| Void | Void Linux |
| Gentoo | Gentoo |

**Supported init systems:** systemd, runit, openrc, s6, dinit

**Ansible version:** ≥ 2.15

**Runtime requirement:** A reachable Teleport cluster (auth server + join token) is required for the service to start successfully. The role will install and configure the agent regardless, but `teleport.service` will fail to join without a live cluster.

## Role Variables

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `teleport_enabled` | `true` | No | Enable/disable the entire role |
| `teleport_version` | `"17.0.0"` | No | Full semver string; used for binary downloads; major version is auto-extracted for package repos |
| `teleport_auth_server` | `""` | **Yes** | Auth/proxy server address, e.g. `auth.example.com:443` |
| `teleport_join_token` | `""` | **Yes** | Join token (static or IAM-based) for cluster registration |
| `teleport_node_name` | `{{ ansible_hostname }}` | No | Node name shown in the Teleport UI |
| `teleport_labels` | `{}` | No | Key-value map of labels for RBAC role assignment |
| `teleport_ssh_enabled` | `true` | No | Enable the SSH service on this node |
| `teleport_proxy_mode` | `false` | No | Run as a proxy node instead of a regular SSH node |
| `teleport_session_recording` | `"node"` | No | Session recording location: `node`, `proxy`, or `off` |
| `teleport_enhanced_recording` | `false` | No | Enable BPF-based enhanced session recording (requires kernel ≥ 5.8) |
| `teleport_export_ca_key` | `true` | No | Export Teleport user CA and configure `ssh` role integration |
| `teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | No | Destination path for the exported CA public key |

## Installation Methods

The install method is determined per OS family by `vars/<os_family>.yml` — not user-facing:

| OS Family | Distros | Method | Notes |
|-----------|---------|--------|-------|
| Archlinux | Arch | `package` | Installs `teleport-bin` from AUR (requires AUR helper or pre-installed package) |
| Debian | Debian, Ubuntu | `repo` | Adds `apt.releases.teleport.dev` APT repo then installs `teleport` |
| RedHat | Fedora, RHEL | `repo` | Adds `yum.releases.teleport.dev` YUM repo then installs `teleport` |
| Void | Void Linux | `binary` | Downloads tarball from `cdn.teleport.dev`, extracts to `/usr/local/bin/` |
| Gentoo | Gentoo | `binary` | Same as Void; no official Gentoo package available |

`teleport_version` controls the version fetched for `repo` and `binary` methods (major version for repos, full semver for binary URLs).

## Usage

Minimal playbook — provide the two required variables:

```yaml
- name: Deploy workstation
  hosts: workstations
  become: true
  roles:
    - role: teleport
      vars:
        teleport_auth_server: "auth.example.com:443"
        teleport_join_token: "{{ vault_teleport_join_token }}"
```

With labels and enhanced recording:

```yaml
- role: teleport
  vars:
    teleport_auth_server: "auth.example.com:443"
    teleport_join_token: "{{ vault_teleport_join_token }}"
    teleport_labels:
      env: production
      role: workstation
    teleport_session_recording: "proxy"
    teleport_enhanced_recording: true
```

**Run order:** When using the `ssh` role alongside this role, `teleport` must run first so the CA fact is available before `sshd_config` is rendered.

## Service Management

The Teleport agent is enabled and started as part of the role. The service name is mapped per init system in `vars/<os_family>.yml` (all supported init systems map to `teleport`).

> **Important:** The service requires a reachable auth server and a valid join token to start successfully. If neither is available (e.g. in CI or staging environments), set `teleport_enabled: false` or mock the variables and skip the service step with `--skip-tags teleport,service`.

To restart the service without re-applying the full configuration:

```
ansible-playbook workstation.yml --tags teleport,service
```

## CA Export and `ssh` Role Integration

When `teleport_export_ca_key: true` (the default), the role:

1. Reads the Teleport user CA public key from the auth server via `tctl auth export`.
2. Writes it to `teleport_ca_keys_file` (default: `/etc/ssh/teleport_user_ca.pub`).
3. Sets the Ansible fact `ssh_teleport_integration: true`.

The `ssh` role detects this fact and adds:

```
TrustedUserCAKeys /etc/ssh/teleport_user_ca.pub
```

to `sshd_config`, allowing Teleport-issued short-lived certificates to authenticate without pre-deployed `authorized_keys` entries. This is the recommended zero-trust configuration.

Set `teleport_export_ca_key: false` if the `ssh` role is not in use or if managing `sshd_config` separately.

## Tags

| Tag | Scope |
|-----|-------|
| `teleport` | All tasks |
| `teleport`, `install` | Package/binary installation only |
| `teleport`, `security` | Join token validation and CA export |
| `teleport`, `service` | Service enable/start only |
| `teleport`, `report` | Execution report (skippable in CI) |

## Testing (Molecule)

Three scenarios covering offline validation, containerized systemd, and full VM testing:

| Scenario | Driver | Platform | What is tested |
|----------|--------|----------|----------------|
| `default` | `default` (localhost) | Localhost (Arch) | Syntax, variable loading, config file rendered with correct content and `0600` permissions, data directory exists |
| `docker` | Docker | `arch-systemd` container | All of the above plus: package install, service enabled/running, idempotency |
| `vagrant` | Vagrant | Arch Linux VM + Ubuntu Noble VM | Multi-distro install paths (`package` on Arch, `repo` on Ubuntu), service join (requires mock cluster or skip) |

**What is not testable without a live Teleport cluster:**

- Actual cluster join (`teleport.service` reaching `Running` state)
- CA export (`teleport_export_ca_key: true`) — requires `tctl` connected to a live auth server
- Session recording validation

Run a scenario:

```bash
cd ansible/roles/teleport
molecule test -s default      # offline smoke test
molecule test -s docker       # containerized systemd (requires Docker)
molecule test -s vagrant      # full VM (requires Vagrant + libvirt/VirtualBox)
```

## Known Limitations

| Limitation | Details |
|------------|---------|
| AUR package not testable in CI | `teleport-bin` is an AUR package; standard CI containers use official repos or binary installs |
| Service requires live cluster | `teleport.service` will fail to reach `Running` without a valid `auth_server` + `join_token` |
| Binary install lacks service unit | Void/Gentoo binary installs do not include a systemd unit; a service unit must be provided separately if systemd is the init system |
| `tctl` dependency for CA export | CA export requires `tctl` to be available and authenticated against the cluster; not available in offline/CI runs |
| Enhanced recording kernel requirement | BPF-based enhanced session recording (`teleport_enhanced_recording: true`) requires Linux kernel ≥ 5.8 with BTF enabled |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
