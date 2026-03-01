# ssh

Hardened OpenSSH server configuration based on dev-sec.io, CIS Benchmark, DISA STIG, and Mozilla Modern SSH guidelines.

## What this role does

- [x] Installs OpenSSH server (package name mapped per OS family)
- [x] Preflight lockout protection: verifies user membership in `AllowGroups`/`AllowUsers`/`DenyGroups`/`DenyUsers` before applying hardening; warns if `~user/.ssh/authorized_keys` is absent when password auth is disabled
- [x] Deploys `sshd_config` from Jinja2 template with modern-only cryptography
- [x] Removes weak host keys (DSA, ECDSA)
- [x] Configures modern cryptography: ChaCha20-Poly1305 / AES-GCM ciphers, ETM MACs, Curve25519 KEX
- [x] Optional DH moduli cleanup (removes primes smaller than 3072 bits)
- [x] Optional SSH banner deployment (`/etc/issue.net`)
- [x] Init-system agnostic service management (systemd, runit, openrc, s6, dinit)
- [x] Optional Teleport SSH CA integration (`TrustedUserCAKeys`)
- [x] Validates `sshd_config` syntax (`sshd -t`) and verifies service is running

## Variables

### General

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_harden_sshd` | `true` | Master switch — deploy hardened `sshd_config` |
| `ssh_port` | `22` | SSH server port |
| `ssh_address_family` | `"inet"` | Address family: `inet`, `inet6`, or `any` |
| `ssh_listen_addresses` | `[]` | Listen addresses; empty = all interfaces |

### Host keys

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_host_keys` | `[ed25519, rsa]` | Paths to host key files (order = negotiation priority) |
| `ssh_host_key_cleanup` | `true` | Remove weak host keys: DSA and ECDSA |

### Cryptography

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_kex_algorithms` | curve25519-sha256, DH group16/18, DH group-exchange-sha256 | Key exchange algorithms |
| `ssh_ciphers` | chacha20-poly1305, aes256-gcm, aes128-gcm | Symmetric ciphers (AEAD only) |
| `ssh_macs` | hmac-sha2-512-etm, hmac-sha2-256-etm, umac-128-etm | Message authentication codes (ETM only) |
| `ssh_host_key_algorithms` | ssh-ed25519, rsa-sha2-512, rsa-sha2-256 | Offered host key algorithms |
| `ssh_rekey_limit` | `"512M 1h"` | Renegotiate session keys after this volume or time |

### Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_login_grace_time` | `60` | Seconds to complete authentication before disconnect |
| `ssh_permit_root_login` | `"no"` | Root login: `no`, `prohibit-password`, `without-password`, `yes` |
| `ssh_strict_modes` | `"yes"` | Check `~/.ssh` permissions before accepting keys |
| `ssh_max_auth_tries` | `3` | Failed authentication attempts before disconnect |
| `ssh_max_sessions` | `10` | Maximum sessions per connection |
| `ssh_pubkey_authentication` | `"yes"` | Allow public key authentication |
| `ssh_password_authentication` | `"no"` | Allow password authentication |
| `ssh_permit_empty_passwords` | `"no"` | Permit empty passwords (CIS, DISA STIG: must be `no`) |
| `ssh_hostbased_authentication` | `"no"` | Allow `.rhosts`/`.shosts` host-based authentication |
| `ssh_ignore_rhosts` | `"yes"` | Ignore `.rhosts` and `.shosts` files |
| `ssh_kbd_interactive_authentication` | `"no"` | PAM keyboard-interactive authentication (replaces deprecated `ChallengeResponseAuthentication` removed in OpenSSH 9.5+) |
| `ssh_authentication_methods` | `"publickey"` | Required authentication methods |
| `ssh_permit_user_environment` | `"no"` | Honour `~/.ssh/environment` (blocks `LD_PRELOAD`/`PATH` injection) |
| `ssh_use_pam` | `"yes"` | Use PAM for account and session management |

### Access control

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_user` | `"{{ ansible_user_id }}"` | User to verify against lockout checks (default: current Ansible user) |
| `ssh_allow_groups` | `["wheel"]` | Groups permitted SSH access (whitelist; empty = all) |
| `ssh_allow_users` | `[]` | Users permitted SSH access (whitelist; empty = per groups) |
| `ssh_deny_groups` | `[]` | Groups denied SSH access (blacklist) |
| `ssh_deny_users` | `[]` | Users denied SSH access (blacklist) |

### Forwarding and tunnels

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_x11_forwarding` | `"no"` | X11 forwarding (mitigates X11 sniffing) |
| `ssh_allow_tcp_forwarding` | `"no"` | TCP port forwarding (mitigates firewall bypass) |
| `ssh_allow_agent_forwarding` | `"no"` | SSH agent forwarding (mitigates key theft) |
| `ssh_permit_tunnel` | `"no"` | tun-device VPN tunnels |
| `ssh_gateway_ports` | `"no"` | Allow remote hosts to connect to forwarded ports |

### Logging

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_log_level` | `"VERBOSE"` | Log level; `VERBOSE` records key fingerprint per login (CIS, DISA) |
| `ssh_syslog_facility` | `"AUTH"` | syslog facility |

### Session

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_client_alive_interval` | `300` | Keepalive interval from server to client (seconds) |
| `ssh_client_alive_count_max` | `2` | Keepalive messages without response before disconnect |
| `ssh_tcp_keepalive` | `"no"` | TCP-level keepalive (less reliable than `ClientAlive`) |
| `ssh_print_motd` | `"no"` | Show MOTD on login |
| `ssh_print_last_log` | `"yes"` | Show last login time on login |
| `ssh_accept_env` | `"LANG LC_*"` | Client environment variables accepted by the server |

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_use_dns` | `"no"` | Reverse-resolve client IP (slows login, no security benefit) |
| `ssh_compression` | `"no"` | Traffic compression (disabled — CRIME-class attack vector) |
| `ssh_max_startups` | `"10:30:60"` | Unauthenticated connection throttle: start:rate:full (CIS/Mozilla) |

### Banner

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_banner_enabled` | `false` | Deploy a pre-authentication banner |
| `ssh_banner_path` | `"/etc/issue.net"` | Path to banner file |
| `ssh_banner_text` | legal warning | Banner content deployed to `ssh_banner_path` |

### SFTP

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_sftp_enabled` | `true` | Enable the SFTP subsystem |
| `ssh_sftp_server` | `"internal-sftp"` | SFTP server binary (`internal-sftp` supports chroot) |
| `ssh_sftp_chroot_enabled` | `false` | Restrict a group to a chroot SFTP jail |
| `ssh_sftp_chroot_group` | `"sftponly"` | Group subject to chroot restriction |
| `ssh_sftp_chroot_directory` | `"/home/%u"` | Chroot path (`%u` = username) |

### DH moduli cleanup

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_moduli_cleanup` | `false` | Remove DH primes smaller than `ssh_moduli_minimum_bits` from `/etc/ssh/moduli` |
| `ssh_moduli_minimum_bits` | `3072` | Minimum DH prime size in bits (NIST/Mozilla recommendation) |

### Teleport integration

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_teleport_integration` | `false` | Trust Teleport user CA (set automatically by the `teleport` role) |
| `ssh_teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | Path to Teleport user CA public key |

## Compliance

| Standard | Coverage |
|----------|---------|
| **dev-sec.io SSH baseline** | Cryptography suite, host key cleanup, auth hardening, forwarding restrictions |
| **CIS Benchmark** | `LogLevel VERBOSE` (4.2.3), `MaxAuthTries 3` (5.2.7), `PermitEmptyPasswords no` (5.2.11), `MaxStartups 10:30:60` |
| **DISA STIG** | `LogLevel VERBOSE` (V-238202), `PermitEmptyPasswords no` (V-238204), `StrictModes yes` |
| **Mozilla Modern SSH** | Cipher/MAC/KEX list, `RekeyLimit`, DH moduli cleanup |

## Supported platforms

Arch Linux, Debian/Ubuntu, RedHat/EL, Void Linux, Gentoo

## Init systems

systemd, runit, openrc, s6, dinit

## Tags

| Tag | Purpose |
|-----|---------|
| `ssh` | All tasks |
| `ssh`, `install` | Package installation only |
| `ssh`, `security` | Preflight check and sshd hardening |
| `ssh`, `moduli` | DH moduli cleanup only |
| `ssh`, `banner` | Banner deployment only |
| `ssh`, `service` | Service enable/start only |
| `ssh`, `report` | Execution report |

## Testing

Tests use [Molecule](https://molecule.readthedocs.io/) with three scenarios.
Shared playbooks live in `molecule/shared/` and are reused across all scenarios.

| Scenario | Driver | Platform | Purpose |
|----------|--------|----------|---------|
| `default` | localhost | local machine | Fast syntax + functional check (no daemon restart) |
| `docker` | Docker | `arch-systemd` container (PID 1 = systemd) | Full systemd lifecycle, service running+enabled |
| `vagrant` | Vagrant (libvirt) | Arch Linux + Ubuntu 24.04 VMs | Cross-distro integration (Arch `sshd.service` / Debian `ssh.service`) |

### Run tests

```bash
# Default (localhost)
cd ansible && molecule test -s default

# Docker (requires running Docker daemon and arch-systemd image)
molecule test -s docker

# Vagrant (requires libvirt/KVM)
molecule test -s vagrant
```

### Verify assertions (56 total)

Package install, service enabled+running, `sshd_config` permissions (0600/root),
41 security directive checks (all major hardening directives including
`KbdInteractiveAuthentication`, `TCPKeepAlive`, `PrintMotd`, `PrintLastLog`,
`MaxSessions`, `AcceptEnv`), cryptography suite (positive + negative),
host key presence (ed25519+RSA with 0600) and absence (DSA/ECDSA),
`RekeyLimit 512M 1h` value check, banner file + content + config directive,
`AllowGroups` absent when empty, SFTP subsystem, `sshd -t` syntax validation,
and Ansible managed comment.

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
