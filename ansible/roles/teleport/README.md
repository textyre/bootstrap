# teleport

Installs Teleport and configures the machine either as a complete single-node
cluster or as an SSH agent of an existing cluster.

## Execution Flow

1. **Validate** (`tasks/validate.yml`) -- accepts the five project OS families, the `standalone` or `agent` mode, a compatible installation method, and systemd when the role owns the service. Agent mode must have an auth server and join token.
2. **Load vars** (`tasks/load_vars.yml`) -- loads the package mapping for the detected OS family.
3. **Install** (`tasks/install.yml`) -- uses configured packages, the official Debian/RedHat repository, or a checksum-verified Teleport archive. Binary installation deploys only the published Teleport executables; temporary files are removed in the same block.
4. **Configure** (`tasks/configure.yml`) -- creates `/var/lib/teleport` and renders `/etc/teleport.yaml`. Existing cluster data is never removed.
5. **Service** (`tasks/service/systemd.yml`) -- deploys the binary-install unit, reloads systemd when needed, enables Teleport, starts it, and restarts it immediately when the binary, unit, or configuration changed. The role has no handlers.
6. **Verify** (`tasks/verify.yml`) -- runs the installed binary, asks Teleport to parse the rendered configuration, and verifies that a managed service remains active.
7. **CA export** (`tasks/ca_export.yml`) -- optionally exports the running cluster's user CA after service startup, removes the `cert-authority` marker from `tctl` output as required by `TrustedUserCAKeys`, and writes the resulting public key for OpenSSH.
8. **Report** (`tasks/report.yml`) -- renders the final execution report without calculating role state.

## Operating Modes

| Mode | Services on this machine | Required input | User-visible result |
|------|--------------------------|----------------|---------------------|
| `standalone` | Auth, Proxy, and SSH | None | The machine is a complete Teleport cluster. Users connect to its proxy and the same machine is available as an SSH node |
| `agent` | SSH, plus optional Proxy | `teleport_auth_server`, `teleport_join_token` | The machine joins an existing Teleport cluster and becomes an SSH resource in that cluster |

Teleport and OpenSSH are separate access services. Teleport can provide its own
SSH endpoint without `sshd`. When CA export is enabled, the later `ssh` role also
configures OpenSSH to accept certificates issued by the Teleport user CA.

## Variables

Override these through inventory. Values in `vars/` are internal implementation
details.

| Variable | Default | Meaning |
|----------|---------|---------|
| `teleport_mode` | `standalone` | Selects a complete local cluster or an agent joining an existing cluster |
| `teleport_install_method` | `repo` on Debian, otherwise `binary` | Selects official repository, configured distro package, or checksum-verified archive installation. RHEL can explicitly select its official repository; Fedora uses binary because Teleport does not publish a Fedora YUM path |
| `teleport_manage_install` | `true` | `false` leaves an externally installed Teleport untouched; the binary must still exist for verification and service use |
| `teleport_manage_config` | `true` | `false` preserves an externally managed `/etc/teleport.yaml`; that file must still be valid |
| `teleport_manage_service` | `true` | `false` leaves service lifecycle external and skips the active-service check |
| `teleport_version` | `17.7.23` | Pins the current supported v17 binary patch and selects repository channel `v17`; repositories may provide a newer patch from that channel |
| `teleport_auth_server` | `""` | Existing Auth/Proxy endpoint used only in agent mode, for example `teleport.example.com:443` |
| `teleport_join_token` | `""` | Token used by an agent for its first cluster registration; treat it as a secret |
| `teleport_node_name` | `{{ ansible_hostname }}` | Node name displayed to Teleport users and used by `tsh ssh` |
| `teleport_labels` | `{}` | Static node labels used by Teleport RBAC and resource selection |
| `teleport_auth_listen_addr` | `0.0.0.0:3025` | Standalone Auth API listener used by Teleport services |
| `teleport_proxy_listen_addr` | `0.0.0.0:3080` | Standalone HTTPS proxy and Web UI listener |
| `teleport_proxy_public_addr` | `{{ ansible_hostname }}:3080` | Address advertised to clients; set a resolvable DNS name for remote use |
| `teleport_ssh_enabled` | `true` | Enables Teleport's SSH node service |
| `teleport_proxy_mode` | `false` | Also enables Proxy service in agent mode; it does not affect standalone, where Proxy is required |
| `teleport_session_recording` | `node` | Recording location: `node`, `node-sync`, `proxy`, `proxy-sync`, or `off` |
| `teleport_enhanced_recording` | `false` | Enables Teleport's Linux enhanced session recording under `ssh_service`; it needs a compatible kernel, BPF, and cgroup v2 environment |
| `teleport_export_ca_key` | `false` | Exports the user CA with local administrative `tctl` access after Teleport is running |
| `teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | Destination read by OpenSSH `TrustedUserCAKeys` when playbook integration is enabled |
| `teleport_config_overwrite` | `{}` | Recursively overrides generated `teleport.yaml` keys; invalid combinations are rejected by Teleport's config parser |

The defaults follow Teleport 17's documented single-node behavior, service
ports, node enrollment, session-recording modes, and enhanced-recording schema:
[CLI reference](https://goteleport.com/docs/ver/17.x/reference/cli/teleport/),
[configuration reference](https://goteleport.com/docs/ver/17.x/reference/config/),
and [Linux installation](https://goteleport.com/docs/installation/linux/).
The previous `17.5.1` default is not retained because
[Teleport identifies `17.5.2` as the first v17 patch for CVE-2025-49825](https://support.goteleport.com/hc/en-us/articles/42280478593043-CVE-2025-49825-for-Cloud-Customers).

## Examples

The default deployment is a standalone cluster:

```yaml
- role: teleport
```

Configure a workstation as an agent of an existing cluster:

```yaml
teleport_mode: agent
teleport_auth_server: teleport.example.com:443
teleport_join_token: "{{ vault_teleport_join_token }}"
teleport_labels:
  environment: home
  type: workstation
```

Export the standalone cluster user CA for the project OpenSSH role:

```yaml
teleport_export_ca_key: true
```

`workstation.yml` runs `teleport` before `ssh`. When export is enabled and
succeeds, it passes the CA path explicitly to `ssh`; no cross-role fact is used.

## Contract And Environments

The role owns Teleport installation, `/etc/teleport.yaml`,
`/var/lib/teleport` directory metadata, the binary-install systemd unit,
Teleport service state, and optional user-CA export. It does not remove cluster
state, create Teleport users or roles, issue join tokens, configure firewall or
DNS, or replace OpenSSH policy.

| Environment | Behavior |
|-------------|----------|
| Bare metal | Runs the complete standalone or agent contract under systemd |
| VM guest | Same behavior as bare metal; virtualization does not change Teleport's access model |
| Docker test container | Supported only by the role's privileged systemd test image; an ordinary application container has no systemd service contract |

The role recognizes Archlinux, Debian, RedHat, Void, and Gentoo. Service
management is currently implemented only for systemd; other init systems fail
explicitly when `teleport_manage_service` is true. Automated coverage is Arch
Linux and Ubuntu.

| OS family | Default installation | Notes |
|-----------|----------------------|-------|
| Archlinux | Verified binary archive | `teleport-bin` is available only when an operator deliberately selects `package` and provides it through a configured package source |
| Debian/Ubuntu | Official APT repository | Repository channel follows the major component of `teleport_version` |
| RedHat/Fedora | Verified binary archive | RHEL may explicitly select `repo`; Fedora is not listed in Teleport's supported YUM repository matrix |
| Void | Verified binary archive | systemd service management is unavailable on a normal Void installation |
| Gentoo | Verified binary archive | systemd is required when the role owns the service |

## Testing

All Ansible and Molecule execution uses the project remote VM or CI path, never
the local workstation.

| Scenario | Coverage |
|----------|----------|
| Default | Standalone binary installation, service convergence, idempotence, HTTPS Proxy API, local cluster status, and user-CA export |
| Docker | Arch standalone behavior through binary installation plus Ubuntu agent configuration through the official APT repository, without a fake external cluster |
| Vagrant/libvirt | The same matrix in real Arch and Ubuntu systemd VMs |

The Ubuntu agent test sets `teleport_manage_service: false` because no external
Teleport cluster exists in the isolated scenario. The role still installs the
real binary and Teleport itself parses the generated agent configuration.
Molecule does not repeat template ownership, mode, or unit-file assertions that
are already guaranteed by Ansible modules.

Success requires convergence, a zero-change idempotence pass, and behavioral
verification. Use the project's changed-role CI workflow or remote Taskfile
entrypoint.

## Troubleshooting

| Symptom | What it means | Action |
|---------|---------------|--------|
| Agent validation requires auth server and token | Agent mode cannot enroll without an existing cluster and join credential | Set both values from the target cluster; do not invent a local placeholder in production |
| Configuration validation fails | Teleport rejected `/etc/teleport.yaml`, including any `teleport_config_overwrite` content | Run `teleport configure --test /etc/teleport.yaml` and correct the reported field |
| Service does not remain active | Teleport parsed the file but failed during runtime initialization | Inspect `journalctl -u teleport -n 100` for bind, data, certificate, or cluster-connectivity errors |
| Standalone UI is unreachable | Proxy is not reachable at the advertised/listen address | Check service logs, firewall port 3080, DNS, and `teleport_proxy_public_addr` |
| CA export fails | Local `tctl` lacks administrative access to a running Auth service | Enable export only on a suitable Auth node or provide a valid administrative identity |
| Binary checksum fails | The archive does not match Teleport's published SHA-256 file | Treat it as an integrity failure; do not bypass checksum validation |

## License

MIT
