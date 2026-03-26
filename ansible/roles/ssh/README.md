# ssh

Hardened OpenSSH server with modern-only cryptography, key-based authentication, and CIS/STIG-compliant configuration.

## Execution flow

1. **Assert OS** (`tasks/main.yml`) -- fails if `ansible_facts['os_family']` is not in `ssh_supported_os` (Archlinux, Debian, RedHat, Void, Gentoo)
2. **Load OS variables** (`vars/<os_family>.yml`) -- loads package names and service name mappings per distro
3. **Install** (`tasks/install.yml`) -- installs OpenSSH via `ansible.builtin.package` using `ssh_packages` from vars
4. **Report: Install** -- logs install phase via `common/report_phase.yml`
5. **Preflight lockout protection** (`tasks/preflight.yml`) -- verifies current user is in `ssh_allow_groups`/`ssh_allow_users`, not in `ssh_deny_groups`/`ssh_deny_users`; warns if `~/.ssh/authorized_keys` is missing when password auth is disabled. **Fails if** user would be locked out. Skipped when `ssh_harden_sshd: false`
6. **Harden** (`tasks/harden.yml`) -- generates ed25519/RSA host keys if absent, deploys `/etc/ssh/sshd_config` from template with `validate: 'sshd -t -f %s'`, disables `sshdgenkeys.service` (systemd only), removes weak host keys (DSA, ECDSA). **Triggers handler:** `restart sshd` on config or key changes. Skipped when `ssh_harden_sshd: false`
7. **Report: Harden** -- logs hardening phase with port, root login, and password auth settings
8. **DH moduli cleanup** (`tasks/moduli.yml`) -- removes DH primes < `ssh_moduli_minimum_bits` from `/etc/ssh/moduli`. **Triggers handler:** `restart sshd`. Skipped when `ssh_moduli_cleanup: false`
9. **Banner** (`tasks/banner.yml`) -- deploys `ssh_banner_text` to `ssh_banner_path` (`/etc/issue.net`). **Triggers handler:** `reload sshd`. Skipped when `ssh_banner_enabled: false`
10. **Service** (`tasks/service.yml`) -- enables and starts sshd using init-agnostic `ansible.builtin.service` with service name from `ssh_service_name[service_mgr]`
11. **Report: Service** -- logs service phase
12. **Verify** (`tasks/verify.yml`) -- validates sshd_config syntax (`sshd -t`), verifies `PermitRootLogin` via lineinfile check_mode, asserts sshd service is running (init-agnostic)
13. **Report: Final** -- renders execution report via `common/report_render.yml`

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `restart sshd` | Config deploy (step 6), host key generation (step 6), moduli cleanup (step 8) | Restarts sshd service. Flushed after config deploy, before weak key removal (step 6). |
| `reload sshd` | Banner deploy (step 9) | Reloads sshd configuration without dropping connections. |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

#### General

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_harden_sshd` | `true` | safe | Master switch -- set `false` to install only, skip hardening |
| `ssh_manage_crypto` | `true` | safe | Manage cryptographic settings (ciphers, MACs, KEX, host key algorithms, RekeyLimit) |
| `ssh_manage_auth` | `true` | safe | Manage authentication settings (root login, password auth, auth methods, PAM) |
| `ssh_manage_forwarding` | `true` | safe | Manage forwarding and tunnel settings (X11, TCP, agent forwarding, tunnels) |
| `ssh_manage_access_control` | `true` | safe | Manage access control directives (AllowGroups, AllowUsers, DenyGroups, DenyUsers) |
| `ssh_manage_logging` | `true` | safe | Manage logging settings (LogLevel, SyslogFacility) |
| `ssh_manage_session` | `true` | safe | Manage session settings (ClientAlive, TCPKeepAlive, MaxStartups, PrintMotd, etc.) |
| `ssh_port` | `22` | careful | SSH port. Changing requires firewall rule update and client reconfiguration |
| `ssh_address_family` | `"inet"` | careful | `inet` (IPv4), `inet6` (IPv6), or `any`. Restricting to IPv4 reduces attack surface if IPv6 unused |
| `ssh_listen_addresses` | `[]` | careful | Bind addresses; empty = all interfaces. Setting to `["127.0.0.1"]` blocks remote access |

#### Host keys

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_host_keys` | `[ed25519, rsa]` | internal | Host key file paths, order = negotiation priority |
| `ssh_host_key_cleanup` | `true` | careful | Remove DSA and ECDSA host keys. Disabling leaves weak keys on disk |

#### Cryptography

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_kex_algorithms` | curve25519-sha256, DH group16/18/exchange-sha256 | internal | Key exchange algorithms. Removing curve25519 breaks most modern clients |
| `ssh_ciphers` | chacha20-poly1305, aes256-gcm, aes128-gcm | internal | AEAD ciphers only. Adding CBC ciphers weakens security |
| `ssh_macs` | hmac-sha2-512-etm, hmac-sha2-256-etm, umac-128-etm | internal | ETM MACs only. Adding non-ETM MACs enables padding oracle attacks |
| `ssh_host_key_algorithms` | ssh-ed25519, rsa-sha2-512, rsa-sha2-256 | internal | Accepted host key types. Adding ssh-rsa allows SHA-1 signatures |
| `ssh_rekey_limit` | `"512M 1h"` | safe | Session key renegotiation threshold (volume + time) |

#### Authentication

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_login_grace_time` | `60` | safe | Seconds to complete authentication before disconnect |
| `ssh_permit_root_login` | `"no"` | careful | `no`, `prohibit-password`, `without-password`, or `yes`. CIS requires `no` |
| `ssh_strict_modes` | `"yes"` | safe | Check `~/.ssh` ownership and permissions before accepting keys |
| `ssh_max_auth_tries` | `3` | safe | Failed attempts per connection before disconnect (CIS 5.2.7) |
| `ssh_max_sessions` | `10` | safe | Maximum multiplexed sessions per connection |
| `ssh_pubkey_authentication` | `"yes"` | internal | Disable only if you have an alternative auth method |
| `ssh_password_authentication` | `"no"` | careful | Set `"yes"` only if not all users have SSH keys. Preflight warns if keys are missing |
| `ssh_permit_empty_passwords` | `"no"` | internal | Must be `no` (CIS, DISA STIG). Never change |
| `ssh_hostbased_authentication` | `"no"` | internal | Legacy `.rhosts`/`.shosts` method. Never enable |
| `ssh_ignore_rhosts` | `"yes"` | internal | Ignore legacy `.rhosts` files. Never change |
| `ssh_kbd_interactive_authentication` | `"no"` | careful | PAM keyboard-interactive. Replaces deprecated `ChallengeResponseAuthentication` (OpenSSH 9.5+) |
| `ssh_authentication_methods` | `"publickey"` | careful | Required methods. `"publickey,password"` enables 2FA |
| `ssh_permit_user_environment` | `"no"` | internal | Blocks `LD_PRELOAD`/`PATH` injection via `~/.ssh/environment` |
| `ssh_use_pam` | `"yes"` | careful | Needed for account lockout and session limits even without password auth |

#### Access control

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_user` | `"{{ ansible_user_id }}"` | safe | User checked against lockout in preflight |
| `ssh_allow_groups` | `["wheel"]` | careful | Whitelist of groups allowed SSH access. Empty = all groups allowed. Preflight fails if current user not in a listed group |
| `ssh_allow_users` | `[]` | careful | Whitelist of users. Empty = no user-level restriction (group rules apply) |
| `ssh_deny_groups` | `[]` | safe | Blacklist of groups denied SSH access |
| `ssh_deny_users` | `[]` | safe | Blacklist of users denied SSH access |

#### Forwarding and tunnels

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_x11_forwarding` | `"no"` | safe | X11 forwarding. Mitigates X11 sniffing |
| `ssh_allow_tcp_forwarding` | `"no"` | careful | TCP port forwarding. Enable for development jump hosts |
| `ssh_allow_agent_forwarding` | `"no"` | careful | SSH agent forwarding. Mitigates key theft via compromised hosts |
| `ssh_permit_tunnel` | `"no"` | safe | VPN tunnels via tun device |
| `ssh_gateway_ports` | `"no"` | safe | Allow remote hosts to connect to forwarded ports |

#### Logging

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_log_level` | `"VERBOSE"` | safe | `VERBOSE` logs key fingerprint per login (CIS 4.2.3, DISA V-238202) |
| `ssh_syslog_facility` | `"AUTH"` | safe | Syslog facility for auth events |

#### Session

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_client_alive_interval` | `300` | safe | Keepalive interval in seconds. Session timeout = interval * count_max |
| `ssh_client_alive_count_max` | `2` | safe | Keepalive misses before disconnect |
| `ssh_tcp_keepalive` | `"no"` | safe | TCP-level keepalive (less reliable than ClientAlive) |
| `ssh_print_motd` | `"no"` | safe | Show MOTD on login |
| `ssh_print_last_log` | `"yes"` | safe | Show last login time |
| `ssh_accept_env` | `"LANG LC_*"` | safe | Client environment variables accepted |

#### Network

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_use_dns` | `"no"` | safe | Reverse DNS lookup (slows login, no security benefit) |
| `ssh_compression` | `"no"` | safe | Traffic compression (CRIME-class attack vector) |
| `ssh_max_startups` | `"10:30:60"` | safe | DoS throttle: start:rate:full (CIS/Mozilla) |

#### Banner

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_banner_enabled` | `false` | safe | Deploy a pre-authentication legal warning banner |
| `ssh_banner_path` | `"/etc/issue.net"` | safe | Path to banner file |
| `ssh_banner_text` | legal warning | safe | Banner content |

#### SFTP

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_sftp_enabled` | `true` | safe | Enable SFTP subsystem |
| `ssh_sftp_server` | `"internal-sftp"` | safe | SFTP binary (`internal-sftp` supports chroot) |
| `ssh_sftp_chroot_enabled` | `false` | careful | Restrict a group to chroot SFTP jail. Requires directory ownership by root |
| `ssh_sftp_chroot_group` | `"sftponly"` | safe | Group subject to chroot |
| `ssh_sftp_chroot_directory` | `"/home/%u"` | careful | Chroot path (`%u` = username). Must be owned by root |

#### DH moduli

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_moduli_cleanup` | `false` | safe | Remove weak DH primes from `/etc/ssh/moduli` |
| `ssh_moduli_minimum_bits` | `3072` | safe | Minimum prime size in bits (NIST/Mozilla) |

#### Teleport integration

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_teleport_integration` | `false` | safe | Trust Teleport user CA (auto-set by `teleport` role) |
| `ssh_teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | safe | Path to Teleport CA public key |

### Internal mappings (`vars/`)

These files contain per-distro package and service name mappings. Edit only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | Package: `openssh`, service: `sshd` for all init systems | Adding Arch-specific changes |
| `vars/debian.yml` | Packages: `openssh-server` + `openssh-client`, service: `ssh` | Adding Debian-specific changes |
| `vars/redhat.yml` | Packages: `openssh-server` + `openssh-clients`, service: `sshd` | Adding RHEL-specific changes |
| `vars/void.yml` | Package: `openssh`, service: `sshd` | Adding Void-specific changes |
| `vars/gentoo.yml` | Package: `net-misc/openssh`, service: `sshd` | Adding Gentoo-specific changes |

## Examples

### Changing the SSH port

```yaml
# In group_vars/all/ssh.yml or host_vars/<hostname>/ssh.yml:
ssh_port: 2222
```

Update your firewall rules and SSH client config accordingly. The role validates `sshd_config` syntax before applying.

### Enabling password authentication (temporary)

```yaml
# In host_vars/<hostname>/ssh.yml:
ssh_password_authentication: "yes"
ssh_authentication_methods: "publickey,password"
```

- The preflight check warns if `authorized_keys` is missing when password auth is disabled.
- Use this only during initial setup before deploying SSH keys.

### Restricting access to specific users

```yaml
# In group_vars/all/ssh.yml:
ssh_allow_groups:
  - sshusers
  - devops
ssh_deny_users:
  - deploybot
```

The preflight check verifies the Ansible user is in an allowed group before applying changes.

### Enabling SSH banner

```yaml
# In group_vars/all/ssh.yml:
ssh_banner_enabled: true
ssh_banner_text: |
  Authorized access only. All activity is monitored and logged.
```

### Enabling SFTP chroot

```yaml
# In host_vars/<hostname>/ssh.yml:
ssh_sftp_chroot_enabled: true
ssh_sftp_chroot_group: "sftponly"
ssh_sftp_chroot_directory: "/home/%u"
```

The chroot directory must be owned by root. Users in the `sftponly` group will be restricted to their home directory via SFTP only.

### Enabling DH moduli cleanup

```yaml
# In group_vars/all/ssh.yml:
ssh_moduli_cleanup: true
ssh_moduli_minimum_bits: 3072
```

### Disabling hardening (install only)

```yaml
# In host_vars/<hostname>/ssh.yml:
ssh_harden_sshd: false
```

Installs OpenSSH and starts the service with the distribution default configuration.

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | RedHat / Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|-----------------|------------|--------|
| Package(s) | `openssh` | `openssh-server`, `openssh-client` | `openssh-server`, `openssh-clients` | `openssh` | `net-misc/openssh` |
| Service name (systemd) | `sshd` | `ssh` | `sshd` | `sshd` | `sshd` |
| Service name (runit) | `sshd` | `ssh` | `sshd` | `sshd` | `sshd` |
| Service name (openrc) | `sshd` | `ssh` | `sshd` | `sshd` | `sshd` |
| Config path | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` |
| sshdgenkeys service | exists (disabled by role) | N/A | N/A | N/A | N/A |

## Logs

### Log sources

| Source | Location | Contents | Rotation |
|--------|----------|----------|----------|
| sshd auth log | `journalctl -u sshd` (Arch/RH/Void/Gentoo) or `journalctl -u ssh` (Debian) | Login attempts (success/fail), key fingerprints (`VERBOSE`), session open/close | systemd journal rotation |
| auth.log (Debian) | `/var/log/auth.log` | PAM and sshd auth events | logrotate (system default) |
| secure (RHEL) | `/var/log/secure` | PAM and sshd auth events | logrotate (system default) |

### Reading the logs

- Failed logins: `journalctl -u sshd --since "1 hour ago" | grep Failed`
- Key fingerprint for a login: `journalctl -u sshd | grep "Accepted publickey"` -- shows user, IP, and key SHA256 fingerprint
- Current sessions: `who -u` or `ss -tnp | grep ':22'`
- Config syntax errors after manual edit: `sshd -t` (validates without restarting)
- Lockout diagnosis: check `AllowGroups`/`DenyUsers` in sshd_config vs `id -nG <user>`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Pre-flight lockout protection" | User not in `ssh_allow_groups` | Add user to listed group (`usermod -aG wheel <user>`) or adjust `ssh_allow_groups` |
| "Permission denied (publickey)" after role runs | No `authorized_keys` for user, and password auth is disabled | Deploy SSH public key to `~/.ssh/authorized_keys` before running role. Or temporarily set `ssh_password_authentication: "yes"` |
| sshd won't start after hardening | `sshd -t` shows config error | Check `journalctl -u sshd -n 50`. Common: invalid cipher or MAC name on older OpenSSH versions. Remove unsupported algorithms from `ssh_ciphers`/`ssh_macs` |
| "Connection refused" on port 22 | Service not started, or port changed | `ss -tlnp | grep sshd` to check listening port. Verify `ssh_port` matches firewall rules |
| Idempotence failure on host key generation | `ssh-keygen` runs every time | Check if `creates:` argument path exists. Verify host key file permissions (0600 private, 0644 public) |
| SSH connection slow (5-10s delay) | Reverse DNS lookup enabled | Verify `ssh_use_dns: "no"` is applied. Check `sshd_config` for `UseDNS` directive |
| "Too many authentication failures" | Client sends too many keys before the right one | Limit keys offered by client: `ssh -o IdentitiesOnly=yes -i ~/.ssh/correct_key host` |
| X11 forwarding not working | `X11Forwarding no` (default hardening) | Set `ssh_x11_forwarding: "yes"` if needed for GUI applications |
| SFTP chroot fails with "bad ownership" | Chroot directory not owned by root | `chown root:root /home/<user>` and `chmod 755 /home/<user>` |
| Banner not showing | `ssh_banner_enabled: false` (default) | Set `ssh_banner_enabled: true` and re-run the role |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Full systemd lifecycle across 6 platforms: systemd (Arch+Ubuntu), access-control (Arch+Ubuntu), features (Arch+Ubuntu) |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic, services, or init tasks | Real systemd on Arch (`sshd.service`) and Ubuntu (`ssh.service`) VMs with banner + moduli |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with detailed `fail_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Packages | openssh installed per distro (Arch: `openssh`, Debian: `openssh-server`) | TEST-008 |
| Config file | `/etc/ssh/sshd_config` exists, mode 0600, owned by root | TEST-008 |
| Config content | All 30+ security directives verified against role variables | TEST-008, TEST-012 |
| Services | sshd/ssh running + enabled (per distro) | TEST-008 |
| Cryptography | Positive (chacha20, curve25519, ed25519) and negative (CBC, MD5, SHA-1 KEX) | TEST-008, TEST-011 |
| Host keys | ed25519+RSA present (0600/0644), DSA/ECDSA absent | TEST-008 |
| Access control | AllowGroups/AllowUsers/DenyGroups/DenyUsers on access-control platforms | TEST-008 |
| Features | Teleport CA, SFTP chroot, ListenAddress on features platforms | TEST-008 |
| Banner | File exists, content verified, config directive present (banner-enabled platforms) | TEST-008 |
| DH moduli | No primes < 3072 bits after cleanup (moduli-enabled platforms) | TEST-008 |
| Permissions | `/etc/ssh` directory ownership, config 0600 | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `openssh package not found` | Stale package cache in container | Rebuild: `molecule destroy && molecule test -s docker` |
| `sshd.service is not active` | prepare step didn't install sshd or systemd not ready | Run full sequence, not just `molecule converge` |
| Idempotence failure on `sshd_config` deploy | Template produces different output on second run | Check for timestamps or random values in template |
| `Assertion failed: PermitRootLogin` | verify.yml expects variable value but converge overrode it | Ensure converge and verify use same vars_files |
| `sshd -t` fails with "unsupported option" | Cipher or MAC not supported by container's OpenSSH version | Update base image or remove unsupported algorithm from defaults |
| Vagrant: `Python not found` | prepare.yml missing Python install | Check `prepare.yml` has raw Python install for Arch |
| `LOCKOUT RISK` preflight failure | Test user not in allowed groups | Set `ssh_allow_groups: []` in molecule host_vars for test platforms |

## Tags

| Tag | What it runs | Use case | Command example |
|-----|-------------|----------|-----------------|
| `ssh` | Entire role | Full apply | `ansible-playbook playbook.yml --tags ssh` |
| `ssh,install` | Package installation only | Install without hardening | `ansible-playbook playbook.yml --tags "ssh,install"` |
| `ssh,security` | Preflight + harden tasks | Re-apply hardening without reinstall | `ansible-playbook playbook.yml --tags "ssh,security"` |
| `ssh,service` | Service enable/start only | Restart sshd without re-deploying config | `ansible-playbook playbook.yml --tags "ssh,service"` |
| `ssh,banner` | Banner deployment only | Update banner text | `ansible-playbook playbook.yml --tags "ssh,banner"` |
| `ssh,moduli` | DH moduli cleanup only | Re-run moduli filtering | `ansible-playbook playbook.yml --tags "ssh,moduli"` |
| `report` | Execution report tasks | Re-generate execution report | `ansible-playbook playbook.yml --tags report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with inline documentation | No -- override via inventory |
| `vars/archlinux.yml` | Arch Linux package and service names | Only when adding Arch-specific support |
| `vars/debian.yml` | Debian/Ubuntu package and service names | Only when adding Debian-specific support |
| `vars/redhat.yml` | RHEL/Fedora package and service names | Only when adding RHEL-specific support |
| `vars/void.yml` | Void Linux package and service names | Only when adding Void-specific support |
| `vars/gentoo.yml` | Gentoo package and service names | Only when adding Gentoo-specific support |
| `templates/sshd_config.j2` | sshd_config Jinja2 template | When adding new sshd directives |
| `templates/issue.net.j2` | SSH banner template | When changing banner format |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/preflight.yml` | Lockout protection checks | When changing access control logic |
| `tasks/harden.yml` | Host key gen, config deploy, weak key removal | When changing hardening logic |
| `tasks/moduli.yml` | DH moduli filtering | When changing moduli cleanup |
| `tasks/banner.yml` | Banner file deployment | When changing banner deployment |
| `tasks/service.yml` | Service enable/start | When changing service management |
| `tasks/verify.yml` | Post-deploy verification | When adding verification checks |
| `handlers/main.yml` | Service restart/reload handlers | Rarely |
| `molecule/` | Test scenarios (docker + vagrant) | When changing test coverage |

## Compliance

| Standard | Coverage |
|----------|---------|
| **dev-sec.io SSH baseline** | Cryptography suite, host key cleanup, auth hardening, forwarding restrictions |
| **CIS Benchmark** | `LogLevel VERBOSE` (4.2.3), `MaxAuthTries 3` (5.2.7), `PermitEmptyPasswords no` (5.2.11), `MaxStartups 10:30:60`, `PermitRootLogin no` (5.2.10) |
| **DISA STIG** | `LogLevel VERBOSE` (V-238202), `PermitEmptyPasswords no` (V-238204), `StrictModes yes` |
| **Mozilla Modern SSH** | Cipher/MAC/KEX list, `RekeyLimit`, DH moduli cleanup |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
