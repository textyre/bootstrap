# fail2ban

Configures Fail2Ban SSH brute-force protection.

## Contract

The role owns Fail2Ban SSH jail configuration on the host:

- Fail2Ban packages are installed for the detected distribution.
- `/etc/fail2ban/jail.d/sshd.conf` is rendered from role variables.
- Fail2Ban service is enabled and started on systemd hosts.
- Updated jail configuration is reloaded into the running Fail2Ban server.
- Runtime verification confirms that Fail2Ban answers and the `sshd` jail is loaded.

The role does not manage SSH server configuration, users, SSH keys, firewall policy,
centralized logging, or the system log source. Those belong to their owning roles or to
the host platform.

## Execution Flow

1. **Validate** (`tasks/validate.yml`) -- checks supported OS family and init system.
2. **Load vars** (`tasks/load_vars.yml`) -- loads `vars/<os_family>/main.yml`.
3. **Configure** (`tasks/configure/main.yml`) -- installs packages and deploys the `sshd` jail.
4. **Service** (`tasks/configure/service.yml`) -- applies init-specific service policy and reloads Fail2Ban when the jail changed.
5. **Verify** (`tasks/verify.yml`) -- checks `fail2ban-client ping` and `fail2ban-client status sshd`; on failure, collects diagnostics.
6. **Report** -- renders the final execution report through the shared `common` role.

`tasks/main.yml` is only the orchestrator.

## Variables

Override these through inventory. Do not edit role defaults directly.

| Variable | Default | Description |
|----------|---------|-------------|
| `fail2ban_sshd_enabled` | `true` | Enables the SSH jail. |
| `fail2ban_sshd_port` | `{{ ssh_port | default(22) }}` | SSH port monitored by the jail. |
| `fail2ban_sshd_maxretry` | `5` | Failed attempts within `findtime` before banning. |
| `fail2ban_sshd_findtime` | `600` | Time window in seconds for counting failures. |
| `fail2ban_sshd_bantime` | `3600` | Initial ban duration in seconds. |
| `fail2ban_sshd_bantime_increment` | `true` | Enables progressive ban escalation for repeat offenders. |
| `fail2ban_sshd_bantime_maxtime` | `86400` | Maximum progressive ban duration in seconds. |
| `fail2ban_sshd_backend` | `"auto"` | Fail2Ban log backend: `auto`, `systemd`, `polling`, or `pyinotify`. |
| `fail2ban_sshd_banaction` | `""` | Optional Fail2Ban ban action override. Empty uses Fail2Ban default. |
| `fail2ban_ignoreip` | loopback CIDRs | IPs/CIDRs exempt from bans. Keep loopback entries. |

## Internal Vars

| File | Purpose |
|------|---------|
| `vars/main.yml` | Supported OS families and init systems. |
| `vars/archlinux/main.yml` | Arch packages. |
| `vars/debian/main.yml` | Debian/Ubuntu packages. |
| `vars/redhat/main.yml` | RedHat/Fedora packages. |
| `vars/void/main.yml` | Void packages. |
| `vars/gentoo/main.yml` | Gentoo packages. |

## Examples

### Stricter SSH Protection

```yaml
fail2ban_sshd_maxretry: 3
fail2ban_sshd_bantime: 1800
fail2ban_sshd_bantime_maxtime: 172800
```

### Management Network Whitelist

```yaml
fail2ban_ignoreip:
  - 127.0.0.1/8
  - "::1"
  - 10.0.0.0/24
```

### Custom SSH Port

```yaml
fail2ban_sshd_port: 2222
```

If the `ssh` role is also applied, `fail2ban_sshd_port` follows `ssh_port` by default.

## Supported Platforms

| OS family | Packages | Service |
|-----------|----------|---------|
| Archlinux | `fail2ban` | `fail2ban` |
| Debian / Ubuntu | `fail2ban` | `fail2ban` |
| RedHat / Fedora | `fail2ban` | `fail2ban` |
| Void | `fail2ban` | `fail2ban` |
| Gentoo | `net-analyzer/fail2ban` | `fail2ban` |

Supported init systems: `systemd`, `runit`, `openrc`, `s6`, `dinit`.

Only systemd service management is currently implemented. Other supported init systems fail
explicitly with a clear message instead of silently pretending to be configured.

## Testing

The role has Docker and Vagrant Molecule scenarios.

| Scenario | What it proves |
|----------|----------------|
| Docker | Limited install/config scenario on systemd Arch/Ubuntu containers. It creates a dummy auth log for config validation and skips runtime service checks because containers do not reliably provide Fail2Ban firewall/logging runtime. |
| Vagrant | Full runtime scenario on real Arch/Ubuntu VMs: converge, idempotence, Fail2Ban service, and `sshd` jail runtime. |

Molecule verify checks Fail2Ban configuration syntax with `fail2ban-server --test`.
Runtime status is verified by the role itself during Vagrant converge.

## File Map

| File | Purpose |
|------|---------|
| `defaults/main.yml` | External role contract. |
| `vars/main.yml` | Internal supported OS/init constants. |
| `vars/<os_family>/main.yml` | Distro package names. |
| `tasks/main.yml` | Orchestrator only. |
| `tasks/validate.yml` | Input contract validation. |
| `tasks/load_vars.yml` | Distro variable loading. |
| `tasks/configure/main.yml` | Configure pipeline. |
| `tasks/configure/install.yml` | Package installation. |
| `tasks/configure/jail.yml` | Managed `sshd` jail configuration. |
| `tasks/configure/service.yml` | Init-specific service entrypoint and reload on jail changes. |
| `tasks/init/<init>/service.yml` | Init-specific Fail2Ban service state. |
| `tasks/init/systemd/verify_diagnostics.yml` | systemd journal diagnostics for runtime verify failures. |
| `tasks/verify.yml` | Runtime contract verification with diagnostics on failure. |
| `templates/jail_sshd.conf.j2` | Managed `sshd` jail config. |
| `molecule/` | Docker and Vagrant test scenarios. |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Runtime verify fails at `fail2ban-client ping` | Fail2Ban service did not start or cannot read its configuration | Read the diagnostic output from role verify; check Fail2Ban backend, log source, and firewall backend. |
| `sshd` jail is not loaded | Jail config is disabled or Fail2Ban rejected the jail | Check `fail2ban_sshd_enabled`, backend, and `fail2ban-server --test`. |
| Fail2Ban starts but does not ban | Ban action or firewall backend is not functional | Check nftables/iptables/firewalld ownership in the firewall role or host baseline. |
| SSH failures are not detected | Backend/log source mismatch | Use `fail2ban-client get sshd logpath` and align `fail2ban_sshd_backend` with the host logging model. |

## Boundaries

- SSH port changes are owned by the `ssh` role and firewall exposure by the `firewall` role.
- Log source availability is owned by the OS/logging baseline.
- Ban enforcement depends on the host firewall backend.
- Docker tests are intentionally limited and do not prove runtime ban behavior.
