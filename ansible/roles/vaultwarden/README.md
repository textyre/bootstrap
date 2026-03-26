# vaultwarden

Self-hosted Bitwarden-compatible password manager deployed via Docker Compose, reverse-proxied through Caddy.

## Execution flow

1. **Validate** (`tasks/validate.yml`) — asserts `ansible_facts['os_family']` is in the supported list; fails fast on unsupported OS
2. **Load OS variables** — includes `vars/<os_family>.yml` (cron service name, backup packages)
3. **Merge security config** — combines `vaultwarden_security` dict with `vaultwarden_security_overwrite` into `_vaultwarden_security_merged`
4. **Directories** — creates `vaultwarden_base_dir/` (0755), `vaultwarden_base_dir/data/` (0700), `vaultwarden_backup_dir/` (0755, when `vaultwarden_backup_enabled`)
5. **DNS** — adds `127.0.0.1 <domain>` to `/etc/hosts` via `lineinfile`
6. **Admin token** — if `vaultwarden_admin_enabled` and `.admin_token` doesn't exist: generates with `openssl rand -base64 48`, writes to `vaultwarden_base_dir/.admin_token` (0600). Reads back and sets `_vaultwarden_admin_token` fact.
7. **Docker Compose** — deploys `docker-compose.yml` from template. **Triggers handler:** "Restart vaultwarden" if file changes.
8. **Caddy site config** — deploys `vault.caddy` to `caddy_base_dir/sites/vault.caddy`. **Triggers handler:** "Reload caddy" if file changes.
9. **Start** (`molecule-notest`) — runs `docker compose up` via `community.docker.docker_compose_v2`. Skipped in molecule.
10. **Backup** (when `vaultwarden_backup_enabled`) — installs backup packages, deploys `backup.sh` (0700), enables cron service (`molecule-notest`), schedules daily cron job.
11. **Verify** (`tasks/verify.yml`) — checks `/etc/hosts` via lineinfile check_mode, file existence and permissions, admin token length, backup script presence.
12. **Report** — writes execution summary via `common/report_phase.yml` (one call per phase) and `common/report_render.yml`.

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|--------------|
| `restart vaultwarden` | `docker-compose.yml` change (step 7) | Restarts Vaultwarden containers via `docker_compose_v2` |
| `reload caddy` | `vault.caddy` change (step 8) | Reloads Caddy configuration |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `vaultwarden_enabled` | `true` | safe | Set `false` to skip the entire role |
| `vaultwarden_domain` | `"vault.local"` | careful | Caddy virtual host and Vaultwarden `DOMAIN` env var. Changing after deploy requires DNS update and Caddy reload. |
| `vaultwarden_base_dir` | `"/opt/vaultwarden"` | careful | Root directory for compose file, data, and backups. Changing after initial deploy requires migrating existing data. |
| `vaultwarden_docker_network` | `"proxy"` | careful | External Docker network shared with Caddy. Must match `caddy_docker_network`. |
| `vaultwarden_admin_enabled` | `true` | careful | Enable `/admin` panel. Disable after initial setup — leaving enabled in production exposes the admin interface. |
| `vaultwarden_admin_token` | `"{{ vault_vaultwarden_admin_token \| default('') }}"` | safe | Pre-set admin token from vault. If empty, a random token is auto-generated on first run. |
| `vaultwarden_signups_allowed` | `true` | careful | Allow new user registration. Disable after creating your account to prevent others registering. |
| `vaultwarden_security` | see below | careful | Dict of security settings. Override individual keys via `vaultwarden_security_overwrite`. |
| `vaultwarden_security_overwrite` | `{}` | careful | Dict merged on top of `vaultwarden_security`. Use to change individual security parameters. |
| `vaultwarden_backup_enabled` | `true` | safe | Enable scheduled SQLite backup cron job |
| `vaultwarden_backup_dir` | `"/opt/vaultwarden/backups"` | careful | Directory where backup archives are stored. Ensure sufficient disk for retention period. |
| `vaultwarden_backup_keep_days` | `30` | safe | Days to retain backup files before rotation |
| `vaultwarden_backup_cron_hour` | `"3"` | safe | Hour for daily backup cron job (24h format) |
| `vaultwarden_backup_cron_minute` | `"0"` | safe | Minute for daily backup cron job |
| `vaultwarden_profile_admin_enabled` | `false` if `security` profile, else `true` | safe | Profile-aware admin panel default (ROLE-009) |
| `vaultwarden_profile_signups_allowed` | `false` if `security` profile, else `true` | safe | Profile-aware signups default (ROLE-009) |

**`vaultwarden_security` keys:**

| Key | Default | Safety | Description |
|-----|---------|--------|-------------|
| `password_iterations` | `600000` | internal | PBKDF2 iterations for password hashing. OWASP minimum is 310,000 (2023). Lowering weakens security. |
| `login_ratelimit_max_burst` | `5` | safe | Max login attempts before rate limiting |
| `login_ratelimit_seconds` | `60` | safe | Rate-limit window in seconds for login endpoint |
| `admin_ratelimit_max_burst` | `3` | safe | Max admin panel attempts before rate limiting |
| `admin_ratelimit_seconds` | `60` | safe | Rate-limit window in seconds for admin endpoint |

### Internal mappings (`vars/`)

These files contain cross-platform mappings. Do not override via inventory — edit directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | `_vaultwarden_cron_service: cronie`, backup packages | Adding Arch-specific backup tools |
| `vars/debian.yml` | `_vaultwarden_cron_service: cron`, backup packages | Adding Debian-specific backup tools |
| `vars/redhat.yml` | `_vaultwarden_cron_service: crond`, backup packages | Adding RedHat-specific backup tools |
| `vars/void.yml` | `_vaultwarden_cron_service: cronie`, backup packages | Adding Void-specific backup tools |
| `vars/gentoo.yml` | `_vaultwarden_cron_service: cronie`, backup packages | Adding Gentoo-specific backup tools |

## Examples

### Minimal production configuration

```yaml
# In host_vars/server01/vaultwarden.yml:
vaultwarden_domain: "vault.example.com"
vaultwarden_signups_allowed: false   # lock down after creating account
vaultwarden_admin_enabled: false     # disable after initial setup
```

### Using Ansible vault for admin token

```yaml
# In host_vars/server01/vaultwarden.yml:
vaultwarden_domain: "vault.example.com"
```

```yaml
# In host_vars/server01/vault.yml (encrypted with ansible-vault):
vault_vaultwarden_admin_token: "my-secret-token"
```

### Custom security settings

```yaml
# In group_vars/all/vaultwarden.yml:
vaultwarden_security_overwrite:
  password_iterations: 1000000    # increase iterations for better security
  login_ratelimit_max_burst: 3    # stricter rate limiting
```

### Disabling backups

```yaml
# In host_vars/<hostname>/vaultwarden.yml:
vaultwarden_backup_enabled: false
```

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/vaultwarden.yml:
vaultwarden_enabled: false
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Cron service | `cronie` | `cron` | `crond` | `cronie` | `cronie` |
| Cron package | `cronie` | `cron` | `cronie` | `cronie` | `cronie` |
| SQLite package | `sqlite3` | `sqlite3` | `sqlite` | `sqlite` | `sqlite` |
| Docker | from `docker` role dependency | same | same | same | same |
| Config path | `/opt/vaultwarden/docker-compose.yml` | same | same | same | same |
| Data path | `/opt/vaultwarden/data/` | same | same | same | same |

## Logs

### Log sources

| Source | How to access | Contents |
|--------|--------------|---------- |
| Vaultwarden container | `docker logs vaultwarden` | HTTP requests, auth events, admin actions, errors |
| Caddy access log | `journalctl -u caddy` or `/var/log/caddy/` | HTTP access log with status codes |
| Backup cron output | `/var/log/cron` or `journalctl -u crond` | Backup script execution results |
| Backup files | `ls -lh /opt/vaultwarden/backups/` | SQLite backup archives with timestamps |

Vaultwarden itself writes to stdout/stderr — captured by Docker. No file-based log rotation is configured for the container; Docker log rotation applies (configured in Docker daemon).

### Reading the logs

- **Check auth failures:** `docker logs vaultwarden 2>&1 | grep -i "failed\|error\|invalid"`
- **Check backup ran:** `ls -lt /opt/vaultwarden/backups/ | head -5` — most recent backup should be < 24h old
- **Check Caddy is proxying:** `curl -sv https://vault.local 2>&1 | head -30`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at OS assert | `ansible_facts['os_family']` not in supported list | Check `_vaultwarden_supported_os` in defaults. Only Archlinux/Debian/RedHat/Void/Gentoo supported. |
| Container not starting | `docker logs vaultwarden \| tail -50` | Usually wrong `DOMAIN`, missing network `proxy`, or port conflict. Check `docker network ls`. |
| Caddy can't reach vaultwarden | `docker network inspect proxy` | Vaultwarden container must be on the `proxy` network. Check `vaultwarden_docker_network` matches `caddy_docker_network`. |
| Admin panel returns 403 | `cat /opt/vaultwarden/.admin_token` | Token file empty or truncated. Delete the file and re-run the role to regenerate. |
| Backup script not running | `crontab -l; journalctl -u cronie -n 20` | Cron service not started (tagged `molecule-notest` — ensure it's enabled outside molecule). Check `vaultwarden_backup_enabled: true`. |
| Idempotence failure on docker-compose.yml | Two consecutive `molecule converge` runs show `changed` | Template produces non-deterministic output (e.g., `_vaultwarden_admin_token` fact changes between runs). |
| `docker compose up` fails | `docker compose -f /opt/vaultwarden/docker-compose.yml up` | Missing Docker network `proxy`, insufficient disk space, or port 80/443 already bound. |

## Testing

Two scenarios are required for every role. Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| `default` (localhost) | `molecule test -s default` | Smoke test: after changing templates or variables | Syntax, variable loading, directories, DNS, config file rendering |
| `docker` | `molecule test -s docker` | After changing task logic or service management | Full converge + idempotence + verify on Arch + Ubuntu containers |
| `vagrant` | `molecule test -s vagrant` | Before releasing or after OS-specific changes | Real Docker, real cron, Arch + Ubuntu multi-distro |

Tasks tagged `molecule-notest` (Docker Compose `up`, cron service start) are skipped via `--skip-tags molecule-notest` in all molecule scenarios.

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all `ansible.builtin.assert` tasks pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Directories | `base_dir` 0755, `data/` 0700, `backup_dir/` 0755, owned root:root | TEST-008 |
| DNS | `127.0.0.1 <domain>` present in `/etc/hosts` | TEST-008 |
| Admin token | `.admin_token` exists, mode 0600, length >32 chars | TEST-008 |
| Config files | `docker-compose.yml` 0644, Ansible managed header, service config rendered | TEST-008 |
| Caddy config | `vault.caddy` 0644, security headers, reverse_proxy directive | TEST-008 |
| Backup | `backup.sh` 0700 executable, correct content, cron job in crontab | TEST-008 |
| Skip path | `vaultwarden_enabled: false` runs without error | TEST-011 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `UNREACHABLE — docker` | Docker daemon not running on test host | Start Docker: `systemctl start docker` |
| `Assertion — 127.0.0.1 <domain> in /etc/hosts` fails | `/etc/hosts` write failed (unsafe_writes issue) | Check container has write access to `/etc/hosts`; `unsafe_writes: true` is set on the task |
| Idempotence: `docker-compose.yml changed` | Admin token fact changes between plays | Token is read back from file; check `_vaultwarden_admin_token` set_fact runs correctly |
| `Assert admin token is non-empty` fails | Token generation failed or `vaultwarden_admin_enabled: false` | Check `openssl` is available; verify `vaultwarden_admin_enabled: true` in converge vars |
| `Assert Caddy config` fails | `caddy_base_dir` not set, `/opt/caddy/sites/` doesn't exist | Create the sites directory in `prepare.yml` or ensure `caddy` role ran first |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `vaultwarden` | Entire role | Full apply: `ansible-playbook workstation.yml --tags vaultwarden` |
| `secrets` | Directories, DNS, token, compose, caddy tasks | Redeploy config without touching backup: `ansible-playbook workstation.yml --tags vaultwarden,secrets` |
| `vaultwarden,report` | Execution report only | Re-generate report: `ansible-playbook workstation.yml --tags vaultwarden,report` |
| `molecule-notest` | Docker Compose `up`, cron service start | Skipped in molecule automatically — not for direct use |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No — override via inventory |
| `vars/<os_family>.yml` | Cron service name, backup packages per distro | Only when adding distro support |
| `templates/docker-compose.yml.j2` | Vaultwarden Docker Compose template | When changing container config |
| `templates/vault.caddy.j2` | Caddy site config template | When changing reverse proxy config |
| `templates/vaultwarden-backup.sh.j2` | Backup script template | When changing backup logic |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/validate.yml` | OS and variable validation | When adding validation rules |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `handlers/main.yml` | restart/reload handlers | Rarely |
| `molecule/default/` | Localhost smoke test | When changing smoke test coverage |
| `molecule/docker/` | Docker containerized test | When changing Docker test coverage |
| `molecule/vagrant/` | Full VM test | When changing multi-distro coverage |
| `molecule/shared/converge.yml` | Shared converge playbook | When changing test variables |
| `molecule/shared/verify.yml` | Shared verify playbook | When adding verification assertions |
| `requirements.yml` | Role dependencies (common, docker, caddy) | When adding role dependencies |
| `meta/main.yml` | Role metadata and galaxy dependencies | Rarely |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
