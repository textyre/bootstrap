# Vaultwarden Role

The `vaultwarden` role deploys the Vaultwarden password manager as a Docker
Compose application behind the shared Caddy proxy. It owns the application
container, persistent data, local domain mapping, Vaultwarden Caddy site, admin
token lifecycle, security settings, and SQLite backup schedule.

## Security behavior

| Area | Behavior |
|---|---|
| Transport | Runtime verification reaches Vaultwarden through trusted HTTPS |
| Admin access | Stable supplied or one-time generated token; secret files are root-only |
| Registration | Controlled by `vaultwarden_signups_allowed` |
| Authentication | Password hashing and login/admin endpoint rate limits are explicit |
| Proxy response | HSTS, nosniff, SAMEORIGIN, and strict referrer policy headers |
| Persistence | Data is stored below `/opt/vaultwarden/data` with userns-aware ownership |
| Backup | SQLite online backup plus attachment archive and retention |

Docker, global Caddy configuration, firewall ports, and external DNS remain
separate contracts. The workstation playbook orders those roles before
Vaultwarden instead of pulling them through role metadata. Before changing its
own state, Vaultwarden requires an available Docker daemon, a running Caddy
container, and the shared Docker network.

The role supports package mappings for Arch Linux, Ubuntu, Fedora, Void Linux,
and Gentoo. Backup scheduling supports systemd, OpenRC, and runit. Backups on s6
or dinit fail during validation because no scheduler integration is implemented.

Molecule exercises the complete stack on Arch and Ubuntu in both privileged
Docker environments and Vagrant VMs. It verifies the web application over HTTPS
and requires a real database backup to pass SQLite's integrity check rather than
rechecking Ansible-managed files.

The test contract uses Caddy internal TLS. Public ACME issuance, LAN DNS, and
trust installation on client devices remain outside this role's test scope.
