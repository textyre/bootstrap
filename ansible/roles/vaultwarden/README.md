# vaultwarden

Deploys the Vaultwarden password manager behind the shared Caddy reverse proxy.

## Contract

The role requires running Docker and Caddy environments. It manages persistent
Vaultwarden data, a pinned Compose deployment, local name resolution, one Caddy
site, optional admin access, registration policy, authentication rate limits,
and scheduled SQLite backups.

The role does not configure Docker Engine, Caddy's global project, firewall
ports, or external DNS. The workstation playbook applies those owners before
Vaultwarden.

## Pipeline

`validate -> load vars -> install -> configure -> service -> backup -> verify -> report`

The role installs cron and SQLite when backups are enabled. It creates the data
directories, local host record, stable admin token, Compose
project, and Caddy site. Compose applies application changes directly; a changed
site restarts Caddy in the same runtime phase without handlers. Verification
requests `/alive` through Caddy with certificate validation enabled, proving the
container, proxy, DNS, TLS trust, and application endpoint work together.

## Admin token

When `vaultwarden_admin_token` is supplied, the role writes that exact value to
`.admin_token`. Argon2 PHC dollar signs are escaped only in the generated Compose
file so the container receives the original value. Otherwise the role generates
a random plaintext token only when the file does not exist and reuses it on later
runs. Vaultwarden supports this fallback but reports a warning in favor of an
Argon2 PHC token. Secret-bearing files use mode `0600`, and secret task output is
hidden. Disabling the admin interface omits `ADMIN_TOKEN` from the container
environment.

## Variables

All public variables are documented beside their defaults in `defaults/main.yml`.

| Variable | Default | Meaning |
|---|---:|---|
| `vaultwarden_domain` | `vault.local` | HTTPS host and application `DOMAIN` |
| `vaultwarden_base_dir` | `/opt/vaultwarden` | Compose and persistent-data root |
| `vaultwarden_docker_network` | `proxy` | External network shared with Caddy |
| `vaultwarden_docker_image` | `vaultwarden/server:1.36.0` | Pinned application image |
| `vaultwarden_admin_enabled` | `true` | Enable `/admin` |
| `vaultwarden_admin_token` | vault value or empty | Supplied token or one-time generation |
| `vaultwarden_signups_allowed` | `true` | Permit new account registration |
| `vaultwarden_security` | documented defaults | Password hashing and login/admin rate limits |
| `vaultwarden_backup_enabled` | `true` | Install and schedule backups |
| `vaultwarden_backup_dir` | `/opt/vaultwarden/backups` | Protected backup directory |
| `vaultwarden_backup_keep_days` | `30` | Retention period |
| `vaultwarden_backup_cron_hour` | `3` | Daily backup hour |
| `vaultwarden_backup_cron_minute` | `0` | Daily backup minute |
| `vaultwarden_container_uid` | `100000` | Host UID/GID mapped to container root |

The default admin and signup settings support first-time setup. Inventory should
disable both after the intended account has been created. Changing base paths or
container UID on an existing system requires matching data migration/ownership.

## Supported environments

Package mappings exist for Arch Linux, Ubuntu, Fedora, Void Linux, and Gentoo.
The common application pipeline is distro-independent. Backup scheduler service
management supports systemd, OpenRC, and runit; requesting backups on s6 or dinit
fails before the role changes the host.

Docker Engine, Compose V2, the shared `proxy` network, and the Caddy global
project must already be working. Firewall exposure and name resolution for
other devices are separate role or network contracts. The role only maps
`vaultwarden_domain` to loopback on the server itself.

## Backup

The scheduled script uses SQLite's `.backup` command for the database, archives
attachments when present, and removes matching artifacts older than the
retention period. Backup files and their directory are root-only. The role
supports scheduler service management with systemd, OpenRC, and runit; it fails
explicitly on s6 or dinit when backups are requested.

## Tests

`task test-vaultwarden` runs Docker and Vagrant scenarios on Arch and Ubuntu.
Prepare installs and configures Docker as an external prerequisite. Converge
applies Caddy followed by the complete Vaultwarden role and must be idempotent.
Verify requests the real HTTPS web application, checks the Caddy security
headers, runs the backup command, and requires a generated SQLite copy to pass
SQLite's integrity check.

Both scenarios exercise internal TLS. They do not request a public ACME
certificate or configure client-device trust and LAN DNS.

Run all Ansible and Molecule operations through the project's remote VM and
Taskfile workflow.
