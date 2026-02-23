# teleport

Teleport SSH access platform agent — installs and configures a Teleport node for zero-trust SSH access with certificate authority integration.

## What this role does

- [x] Installs Teleport via package manager (Arch), official repository (Debian/RedHat), or binary download (Void/Gentoo)
- [x] Architecture-aware binary downloads: `x86_64` → `amd64`, `aarch64` → `arm64`
- [x] Validates `teleport_auth_server` and `teleport_join_token` before proceeding (fail-fast)
- [x] Deploys `teleport.yaml` with auth server address, join token, node name, and labels
- [x] Configures session recording mode (`node`, `proxy`, or `off`)
- [x] Optional BPF-based enhanced session recording
- [x] Exports Teleport user CA public key and sets the `ssh_teleport_integration` fact for the `ssh` role
- [x] Init-system agnostic service management (systemd, runit, openrc, s6, dinit)
- [x] Verifies Teleport binary version, config file permissions (0600), and service status

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `teleport_enabled` | `true` | Enable/disable the role |
| `teleport_version` | `"17.0.0"` | Full semver; used for binary download; major version auto-extracted for package repos |
| `teleport_auth_server` | `""` | **Required.** Auth/proxy server address, e.g. `auth.example.com:443` |
| `teleport_join_token` | `""` | **Required.** Join token (static or IAM-based) |
| `teleport_node_name` | `{{ ansible_hostname }}` | Node name shown in Teleport UI |
| `teleport_labels` | `{}` | Key-value labels for RBAC role assignment |
| `teleport_ssh_enabled` | `true` | Enable the SSH service on this node |
| `teleport_proxy_mode` | `false` | Run as a proxy node instead of a regular node |
| `teleport_session_recording` | `"node"` | Session recording location: `node`, `proxy`, or `off` |
| `teleport_enhanced_recording` | `false` | Enable BPF-based enhanced session recording |
| `teleport_export_ca_key` | `true` | Export Teleport user CA and configure `ssh` role integration |
| `teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | Path where the exported CA public key is written |

## Integration with the ssh role

When `teleport_export_ca_key: true` (the default), the role:

1. Reads the Teleport user CA public key from the auth server.
2. Writes it to `teleport_ca_keys_file`.
3. Sets the Ansible fact `ssh_teleport_integration: true`.

The `ssh` role picks up this fact and adds `TrustedUserCAKeys {{ ssh_teleport_ca_keys_file }}` to `sshd_config`, allowing Teleport-issued certificates to authenticate without pre-deployed `authorized_keys`.

Run order: `teleport` must execute before `ssh` so the fact is available.

## Supported platforms

Arch Linux, Debian/Ubuntu, RedHat/EL, Void Linux, Gentoo

## Init systems

systemd, runit, openrc, s6, dinit

## Tags

| Tag | Purpose |
|-----|---------|
| `teleport` | All tasks |
| `teleport`, `install` | Package/binary installation only |
| `teleport`, `security` | Join token validation and CA export |
| `teleport`, `service` | Service enable/start only |
| `teleport`, `report` | Execution report |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
