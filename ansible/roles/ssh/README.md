# ssh

Hardened OpenSSH server role.

The role installs OpenSSH, deploys a hardened `sshd_config`, manages supported host keys,
deploys a login banner, and keeps the SSH service enabled and running.

## Contract

The role owns the SSH server configuration on the host:

- OpenSSH server packages are installed for the detected distribution.
- `/etc/ssh/sshd_config` is rendered from role variables and validated with `sshd -t -f %s` before replacement.
- ed25519 and RSA host keys exist when required by the configured algorithms.
- `sshd` is enabled and running using the service name for the detected distribution/init system.
- SSH banner is deployed, and enabled SFTP chroot / Teleport CA settings are rendered into `sshd_config`.

The role does not manage firewall rules, SSH user keys, user creation, group membership, DNS, or Teleport deployment. Those belong to their owning roles.

## Execution Flow

1. **Validate** (`tasks/validate.yml`) -- checks supported OS family and init system.
2. **Load vars** (`tasks/load_vars.yml`) -- loads `vars/<os_family>/main.yml`.
3. **Configure** (`tasks/configure/main.yml`) -- installs packages, checks target user access-control consistency, configures host keys, deploys `sshd_config`, handles banner, and manages service state.
4. **Report** -- renders the final execution report through the shared `common` role.

`tasks/main.yml` is only the orchestrator.

## Variables

Override these through inventory. Do not edit role defaults directly.

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_port` | `22` | SSH server port. Firewall/client changes are outside this role. |
| `ssh_address_family` | `"inet"` | `inet`, `inet6`, or `any`. |
| `ssh_listen_addresses` | `[]` | Optional listen addresses. Empty means OpenSSH default. |

### Host Keys And Crypto

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_host_keys` | ed25519, RSA | Host key files rendered into `sshd_config`. |
| `ssh_kex_algorithms` | modern curve25519/DH list | KEX algorithms. |
| `ssh_ciphers` | chacha20/aes-gcm list | Symmetric ciphers. |
| `ssh_macs` | ETM SHA2/UMAC list | MAC algorithms. |
| `ssh_host_key_algorithms` | ed25519 + rsa-sha2 | Accepted host key algorithms. |
| `ssh_rekey_limit` | `"512M 1h"` | Session key renegotiation limit. |

### Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_login_grace_time` | `60` | Seconds allowed for authentication. |
| `ssh_permit_root_login` | `"no"` | Root login policy. |
| `ssh_strict_modes` | `"yes"` | Enforce ownership/mode checks for user SSH files. |
| `ssh_max_auth_tries` | `3` | Authentication attempts per connection. |
| `ssh_max_sessions` | `10` | Multiplexed sessions per connection. |
| `ssh_pubkey_authentication` | `"yes"` | Public key authentication. |
| `ssh_password_authentication` | `"no"` | Password authentication. |
| `ssh_permit_empty_passwords` | `"no"` | Empty password authentication. |
| `ssh_hostbased_authentication` | `"no"` | Hostbased authentication. |
| `ssh_ignore_rhosts` | `"yes"` | Ignore legacy trust files. |
| `ssh_kbd_interactive_authentication` | `"no"` | Keyboard-interactive authentication. |
| `ssh_authentication_methods` | `"publickey"` | Required authentication methods. |
| `ssh_permit_user_environment` | `"no"` | User-controlled environment files. |
| `ssh_use_pam` | `"yes"` | PAM account/session integration. |

### Access Control

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_user` | `{{ target_user | default(ansible_user_id) }}` | Existing target user checked against Allow/Deny access-control settings before hardening. The role does not create the user, manage groups, or manage keys. |
| `ssh_allow_groups` | `["wheel"]` | Allowed SSH groups. Empty list means no group whitelist. |
| `ssh_allow_users` | `[]` | Allowed SSH users. Empty list means no user whitelist. |
| `ssh_deny_groups` | `[]` | Denied SSH groups. |
| `ssh_deny_users` | `[]` | Denied SSH users. |

### Forwarding, Logging, Session

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_x11_forwarding` | `"no"` | X11 forwarding. |
| `ssh_allow_tcp_forwarding` | `"no"` | TCP port forwarding. |
| `ssh_allow_stream_local_forwarding` | `"no"` | Unix socket forwarding. |
| `ssh_allow_agent_forwarding` | `"no"` | Agent forwarding. |
| `ssh_permit_tunnel` | `"no"` | SSH tunnel device support. |
| `ssh_gateway_ports` | `"no"` | Gateway ports for forwarded sockets. |
| `ssh_log_level` | `"VERBOSE"` | sshd log level. |
| `ssh_syslog_facility` | `"AUTH"` | Syslog facility. |
| `ssh_client_alive_interval` | `300` | Server keepalive interval. |
| `ssh_client_alive_count_max` | `2` | Missed keepalives before disconnect. |
| `ssh_tcp_keepalive` | `"no"` | TCP keepalive. |
| `ssh_print_motd` | `"no"` | Print MOTD. |
| `ssh_print_last_log` | `"yes"` | Print last login. |
| `ssh_accept_env` | `"LANG LC_*"` | Accepted client environment variables. |
| `ssh_use_dns` | `"no"` | Reverse DNS lookup. |
| `ssh_compression` | `"no"` | SSH compression. |
| `ssh_max_startups` | `"10:30:60"` | Unauthenticated connection throttle. |

### Optional Features

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_banner_path` | `"/etc/issue.net"` | Banner path. |
| `ssh_banner_text` | legal warning | Banner content. |
| `ssh_sftp_enabled` | `true` | Enable SFTP subsystem. |
| `ssh_sftp_server` | `"internal-sftp"` | SFTP subsystem command. |
| `ssh_sftp_chroot_enabled` | `false` | Enable SFTP chroot for a group. |
| `ssh_sftp_chroot_group` | `"sftponly"` | Chrooted SFTP group. |
| `ssh_sftp_chroot_directory` | `"/home/%u"` | Chroot directory. |
| `ssh_teleport_integration` | `false` | Trust a Teleport user CA. `workstation.yml` enables this explicitly after a successful Teleport CA export. |
| `ssh_teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | Teleport user CA path. |

### Internal Vars

| File | Purpose |
|------|---------|
| `vars/main.yml` | Supported OS families and init systems. |
| `vars/archlinux/main.yml` | Arch package and service mapping. |
| `vars/debian/main.yml` | Debian/Ubuntu package and service mapping. |
| `vars/redhat/main.yml` | RedHat/Fedora package and service mapping. |
| `vars/void/main.yml` | Void package and service mapping. |
| `vars/gentoo/main.yml` | Gentoo package and service mapping. |

## Examples

### Change SSH Port

```yaml
ssh_port: 2222
```

Firewall and client configuration are outside this role.

### Temporary Password Authentication

```yaml
ssh_password_authentication: "yes"
ssh_authentication_methods: "publickey,password"
```

### Access Control

```yaml
ssh_allow_groups:
  - sshusers
  - devops
ssh_deny_users:
  - deploybot
```

The role checks that existing `ssh_user` is not locked out before applying access-control directives.

### Banner

```yaml
ssh_banner_text: |
  Authorized access only. All activity is monitored and logged.
```

### SFTP Chroot

```yaml
ssh_sftp_chroot_enabled: true
ssh_sftp_chroot_group: "sftponly"
ssh_sftp_chroot_directory: "/home/%u"
```

The chroot directory ownership model is managed outside this role.

## Testing

The role has Docker and Vagrant Molecule scenarios.

| Scenario | Command | What it proves |
|----------|---------|----------------|
| Docker | `molecule test -s docker` | Role converges and is idempotent on systemd Arch/Ubuntu containers. |
| Vagrant | `molecule test -s vagrant` | Role converges and is idempotent on real Arch/Ubuntu VMs with systemd services. |

Molecule verify keeps the role-level assertion minimal: `sshd -t` must accept the
generated configuration and `sshd -T` must be able to produce the effective OpenSSH
configuration. Converge and idempotence cover role application and repeatability.

## File Map

| File | Purpose |
|------|---------|
| `defaults/main.yml` | External role contract. |
| `vars/main.yml` | Internal supported OS/init constants. |
| `vars/<os_family>/main.yml` | Distro package and service mappings. |
| `tasks/main.yml` | Orchestrator only. |
| `tasks/validate.yml` | Input contract validation. |
| `tasks/load_vars.yml` | Distro variable loading. |
| `tasks/configure/main.yml` | Configure pipeline. |
| `tasks/configure/install.yml` | Package installation. |
| `tasks/configure/preflight.yml` | Target user access-control consistency checks. |
| `tasks/configure/host_key_policy.yml` | Managed SSH host key policy. |
| `tasks/configure/runtime.yml` | Runtime directories required before `sshd_config` validation. |
| `tasks/configure/sshd_config.yml` | Managed `sshd_config`. |
| `tasks/configure/banner.yml` | Banner deployment. |
| `tasks/configure/service.yml` | Init-specific service policy entrypoint. |
| `tasks/init/<init>/service.yml` | Init-specific sshd service state. |
| `templates/sshd_config.j2` | Managed `sshd_config`. |
| `templates/issue.net.j2` | Optional SSH banner. |
| `molecule/` | Docker and Vagrant test scenarios. |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Target user access-control check fails | `ssh_user` would be rejected by configured Allow/Deny rules | Adjust `ssh_allow_groups`, `ssh_allow_users`, `ssh_deny_groups`, or `ssh_deny_users` before applying. |
| Key-only login fails | No authorized key exists for the user | Deploy keys with the owning user/ssh_keys role. |
| `sshd_config` deployment fails | `sshd -t -f %s` rejected the rendered config | Check changed variables for unsupported directives or algorithms. |
| Service is not reachable | Firewall/client still uses a different port, or service failed outside role control | Check firewall role and `journalctl` for sshd. |

## Compliance

The defaults follow a hardened OpenSSH posture based on dev-sec style hardening, CIS/STIG
controls, and Mozilla modern cryptography guidance: root login disabled, empty passwords
disabled, password auth disabled by default, modern KEX/ciphers/MACs, and verbose auth logging.
