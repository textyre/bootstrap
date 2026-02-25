# fail2ban

Fail2ban brute-force protection with SSH jail, progressive ban escalation, and multi-distro support.

## What this role does

- [x] Installs fail2ban (package name mapped per OS family, including Gentoo's `net-analyzer/fail2ban`)
- [x] Deploys SSH jail configuration (`/etc/fail2ban/jail.d/sshd.conf`) from Jinja2 template
- [x] Progressive ban escalation: `bantime.increment` doubles ban duration on each repeat offence up to a configurable maximum
- [x] Whitelist support (localhost included by default)
- [x] Auto-detects SSH port from the `ssh` role (`ssh_port` variable)
- [x] Init-system agnostic service management (systemd, runit, openrc, s6, dinit)
- [x] Verifies fail2ban is installed, jail config exists with correct permissions, and service is running

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `fail2ban_enabled` | `true` | Enable/disable the role |
| `fail2ban_sshd_enabled` | `true` | Enable the SSH jail |
| `fail2ban_sshd_port` | `{{ ssh_port \| default(22) }}` | Port to monitor; automatically follows the `ssh` role port |
| `fail2ban_sshd_maxretry` | `5` | Failed attempts within `findtime` before banning |
| `fail2ban_sshd_findtime` | `600` | Window for counting failures in seconds (10 minutes) |
| `fail2ban_sshd_bantime` | `3600` | Initial ban duration in seconds (1 hour) |
| `fail2ban_sshd_bantime_increment` | `true` | Double ban duration on each repeat offence |
| `fail2ban_sshd_bantime_maxtime` | `86400` | Maximum ban duration in seconds (24 hours) |
| `fail2ban_sshd_backend` | `auto` | Log backend: `auto`, `systemd`, `pyinotify`, or `polling` |
| `fail2ban_ignoreip` | `[127.0.0.1/8, ::1]` | IPs and CIDRs exempt from banning (whitelist) |

## Progressive ban escalation

With `fail2ban_sshd_bantime_increment: true`, repeat offenders receive exponentially longer bans:

| Offence | Ban duration |
|---------|-------------|
| 1st ban | 1 hour (`bantime`) |
| 2nd ban | 2 hours |
| 3rd ban | 4 hours |
| ... | doubles each time |
| Maximum | 24 hours (`bantime_maxtime`) |

## Supported platforms

Arch Linux, Debian/Ubuntu, RedHat/EL, Void Linux, Gentoo

## Init systems

systemd, runit, openrc, s6, dinit

## Tags

| Tag | Purpose |
|-----|---------|
| `fail2ban` | All tasks |
| `fail2ban`, `install` | Package installation only |
| `fail2ban`, `service` | Service enable/start only |
| `fail2ban`, `report` | Execution report |

## Testing

Three Molecule scenarios are provided. All share `molecule/shared/converge.yml` and `molecule/shared/verify.yml` (20 assertions covering package, config permissions, all template directives, service enabled/active, and `fail2ban-client` runtime checks).

| Scenario | Driver | Platforms | Requirements |
|----------|--------|-----------|-------------|
| `default` | localhost | Arch Linux (current host) | None |
| `docker` | Docker | `arch-systemd` container | Docker, `arch-systemd` image |
| `vagrant` | Vagrant/libvirt | Arch Linux + Ubuntu 24.04 VMs | Vagrant, libvirt |

```bash
# Localhost (fast, runs on the Arch workstation)
molecule test -s default

# Docker (Arch systemd container)
molecule test -s docker

# Vagrant (cross-platform: Arch + Ubuntu VMs)
molecule test -s vagrant
```

All scenarios run: `syntax → create → prepare → converge → idempotence → verify → destroy` (default skips create/prepare/destroy as it runs on localhost).

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
