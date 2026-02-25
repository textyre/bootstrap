# vaultwarden

Self-hosted Bitwarden-compatible password manager deployed via Docker Compose, reverse-proxied through Caddy.

## What this role does

- [x] Creates directory structure (`base_dir`, `data/`, `backups/`) with strict permissions
- [x] Adds `vaultwarden_domain` to `/etc/hosts` for local resolution
- [x] Generates a random admin token (`openssl rand -base64 48`) on first run and stores it at `{{ vaultwarden_base_dir }}/.admin_token` (mode `0600`)
- [x] Reads and exposes the admin token as a fact so docker-compose can consume it without touching an Ansible vault at runtime
- [x] Deploys `docker-compose.yml` from Jinja2 template (Vaultwarden container on Docker network `proxy`)
- [x] Deploys Caddy site config (`vault.caddy`) with HSTS, X-Content-Type-Options, X-Frame-Options, and Referrer-Policy headers
- [x] Starts Vaultwarden via `docker compose up` (skipped in molecule with `molecule-notest` tag)
- [x] Deploys a backup shell script that archives the `data/` directory and rotates backups older than `vaultwarden_backup_keep_days` days
- [x] Schedules the backup script as a root cron job via `cronie`

## Requirements

- Docker Engine must be installed (fulfilled by the `docker` role dependency)
- Caddy must be running and the `sites/` directory (`caddy_base_dir/sites/`) must exist (fulfilled by the `caddy` role dependency)
- Docker network named `{{ vaultwarden_docker_network }}` (default `proxy`) must exist — created by the `caddy` role

## Role variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vaultwarden_enabled` | `true` | Master switch — set to `false` to skip all tasks |
| `vaultwarden_domain` | `"vault.local"` | Caddy virtual host and Vaultwarden `DOMAIN` env var |
| `vaultwarden_base_dir` | `"/opt/vaultwarden"` | Root directory for compose file, data, and backups |
| `vaultwarden_docker_network` | `"proxy"` | External Docker network shared with Caddy |
| `vaultwarden_admin_enabled` | `true` | Enable `/admin` panel (disable after initial setup) |
| `vaultwarden_admin_token` | `"{{ vault_vaultwarden_admin_token \| default('') }}"` | Pre-set admin token; if empty, a random token is auto-generated |
| `vaultwarden_signups_allowed` | `true` | Allow new user registration (disable after creating your account) |
| `vaultwarden_password_iterations` | `600000` | PBKDF2 iteration count for password hashing |
| `vaultwarden_login_ratelimit_max_burst` | `5` | Max login attempts before rate limiting kicks in |
| `vaultwarden_login_ratelimit_seconds` | `60` | Rate-limit window in seconds for login endpoint |
| `vaultwarden_admin_ratelimit_max_burst` | `3` | Max admin panel attempts before rate limiting |
| `vaultwarden_admin_ratelimit_seconds` | `60` | Rate-limit window in seconds for admin endpoint |
| `vaultwarden_backup_enabled` | `true` | Enable scheduled backup cron job |
| `vaultwarden_backup_dir` | `"/opt/vaultwarden/backups"` | Directory where backup archives are stored |
| `vaultwarden_backup_keep_days` | `30` | Number of days to retain backup files |
| `vaultwarden_backup_cron_hour` | `"3"` | Hour for the daily backup cron job |
| `vaultwarden_backup_cron_minute` | `"0"` | Minute for the daily backup cron job |

## Dependencies

```yaml
dependencies:
  - role: docker
  - role: caddy
```

Both roles must run before `vaultwarden` in any play.

## Example playbook

```yaml
- name: Deploy workstation services
  hosts: workstation
  become: true

  vars_files:
    - vault.yml   # contains vault_vaultwarden_admin_token

  roles:
    - role: docker
    - role: caddy
      vars:
        caddy_domain: "{{ vaultwarden_domain }}"
    - role: vaultwarden
      vars:
        vaultwarden_domain: "vault.example.com"
        vaultwarden_signups_allowed: false   # lock down after first user
        vaultwarden_admin_enabled: false     # disable after setup
```

## Testing

Three Molecule scenarios are provided:

| Scenario | Driver | Purpose |
|----------|--------|---------|
| `default` | `localhost` (connection: local) | Fast smoke test on the developer machine |
| `docker` | Docker (`arch-systemd` container) | Full converge + idempotence + verify in ephemeral Arch Linux container |
| `vagrant` | Vagrant + `libvirt` | Full converge + verify on a real Arch Linux VM |

### Run all scenarios

```bash
cd ansible/roles/vaultwarden

# Smoke test (local)
molecule test -s default

# Docker (requires Docker and arch-systemd image)
molecule test -s docker

# Vagrant (requires vagrant + vagrant-libvirt)
molecule test -s vagrant
```

### Individual steps (useful for debugging)

```bash
molecule converge -s docker    # apply role
molecule verify   -s docker    # run assertions
molecule destroy  -s docker    # teardown
```

### What the verify playbook checks

- Base directory exists, owned by `root:root`, mode `0755`
- Data directory exists, owned by `root:root`, mode `0700`
- Backup directory exists, mode `0755`
- Admin token file exists at `{{ vaultwarden_base_dir }}/.admin_token`, mode `0600`
- `docker-compose.yml` deployed with correct content
- Caddy site config deployed at `{{ caddy_base_dir }}/sites/vault.caddy`
- `/etc/hosts` contains the `vaultwarden_domain` entry
- Backup script deployed and executable

Tasks tagged `molecule-notest` (Docker Compose `up`, cronie `start`) are skipped during molecule runs via `--skip-tags molecule-notest`.

## Security notes

- **Admin token**: Auto-generated with `openssl rand -base64 48` if not pre-set via vault. Stored at `{{ vaultwarden_base_dir }}/.admin_token` with mode `0600`. The token is read at play time and injected into the container — it never lives unencrypted in inventory.
- **Disable signups**: Set `vaultwarden_signups_allowed: false` after creating your personal account to prevent others from registering.
- **Disable admin panel**: Set `vaultwarden_admin_enabled: false` after completing initial configuration. The panel is only needed for setup.
- **PBKDF2 iterations**: Default `600000` exceeds the OWASP minimum of 310,000 (2023 recommendation). Increase for higher security; decrease only if the server is underpowered.
- **Rate limiting**: Login and admin endpoints are rate-limited by default (5 bursts / 60 s for login, 3 bursts / 60 s for admin). Adjust via role variables if needed.
- **Headers**: Caddy serves `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, and `Referrer-Policy` for every response.

## Tags

`vaultwarden`, `secrets`

Use `--tags vaultwarden` to apply only this role in a larger playbook.
Use `--skip-tags molecule-notest` to skip service-dependent tasks (used automatically in molecule).
