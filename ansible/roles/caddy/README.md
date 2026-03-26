# caddy

Dockerized HTTPS reverse proxy using [Caddy](https://caddyserver.com/), with automatic TLS (self-signed CA or Let's Encrypt) and a shared Docker network for inter-service communication.

## Execution flow

1. **Validate** (`tasks/validate.yml`) — asserts `ansible_facts['os_family']` is in the supported list; validates `caddy_tls_email` is set when `caddy_tls_mode: acme`; fails fast on unsupported config
2. **Load OS variables** — includes `vars/<os_family>.yml` (CA trust dir, CA cert filename, browser policy dir)
3. **Docker network** — creates `caddy_docker_network` (`community.docker.docker_network`) when `caddy_manage_network: true`
4. **Directories** — creates `caddy_base_dir/` (0755), `sites/` (0755), `data/` (0755), `config/` (0755)
5. **Caddyfile** — deploys `Caddyfile` from template (0644). Includes `admin off`, `local_certs` when `tls_mode=internal`. **Triggers handler:** "Restart caddy" if changed.
6. **docker-compose.yml** — deploys compose file from template (0644) with ports, volumes, and network. **Triggers handler:** "Restart caddy" if changed.
7. **Start** — runs `docker compose up` via `community.docker.docker_compose_v2`.
8. **CA trust** (when `caddy_tls_mode: internal` and `caddy_manage_certs: true`) — extracts Caddy root CA via `docker cp`, copies to OS trust store (0644), triggers `Update CA trust` handler.
9. **Browser trust** (when `caddy_tls_mode: internal` and `caddy_manage_browser_trust: true`) — deploys `policies.json` to Zen Browser distribution directory (best-effort, skips if browser not found).
10. **Verify** (`tasks/verify.yml`) — checks directories, Caddyfile content, docker-compose.yml content, container running state, Caddyfile syntax via `caddy validate`.
11. **Report** — writes execution summary via `common/report_phase.yml` and `common/report_render.yml`.

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|--------------|
| `restart caddy` | `Caddyfile` or `docker-compose.yml` change (steps 5–6) | Restarts Caddy via `docker_compose_v2` |
| `update ca trust` | CA cert deployed to trust store (step 8) | Runs OS-specific `update-ca-trust` or `update-ca-certificates` |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `caddy_enabled` | `true` | safe | Set `false` to skip the entire role |
| `caddy_base_dir` | `"/opt/caddy"` | careful | Root directory for Caddyfile, sites, data, and config. Changing after deploy requires moving existing data volumes. |
| `caddy_https_port` | `443` | careful | Host port mapped to container HTTPS. Changing requires firewall and DNS update. |
| `caddy_http_port` | `80` | careful | Host port mapped to container HTTP (ACME challenge + redirect). |
| `caddy_tls_mode` | `"internal"` | careful | `internal` = self-signed CA (no internet needed); `acme` = Let's Encrypt (requires public DNS and `caddy_tls_email`). |
| `caddy_tls_email` | `""` | careful | Email for Let's Encrypt. Required when `caddy_tls_mode: acme`. |
| `caddy_docker_network` | `"proxy"` | careful | Docker network shared with backend services. Must match `<role>_docker_network` in all proxied roles. |
| `caddy_docker_image` | `"caddy:2-alpine"` | careful | Docker image. Changing triggers container restart. |
| `caddy_manage_network` | `true` | safe | Create Docker network. Set `false` if network is managed elsewhere. |
| `caddy_manage_certs` | `true` | careful | Copy root CA to system trust store (`internal` mode only). Disable if cert management is handled externally. |
| `caddy_manage_browser_trust` | `true` | safe | Deploy Zen Browser enterprise root policy. No-op if Zen Browser is not installed. |

### Internal mappings (`vars/`)

These files contain OS-specific paths. Do not override via inventory — edit directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|--------------|
| `vars/main.yml` | `_caddy_ca_cert_filename` | Rarely — only to rename the deployed cert |
| `vars/archlinux.yml` | CA trust dir, browser policy dir, CA update command | Adding Arch-specific paths |
| `vars/debian.yml` | CA trust dir, browser policy dir, CA update command | Adding Debian-specific paths |
| `vars/redhat.yml` | CA trust dir, browser policy dir, CA update command | Adding RedHat-specific paths |
| `vars/void.yml` | CA trust dir, browser policy dir, CA update command | Adding Void-specific paths |
| `vars/gentoo.yml` | CA trust dir, browser policy dir, CA update command | Adding Gentoo-specific paths |

## Examples

### Internal TLS (default, self-signed CA)

```yaml
# In host_vars/server01/caddy.yml:
caddy_tls_mode: internal
caddy_docker_network: proxy
```

### ACME (Let's Encrypt)

```yaml
# In host_vars/server01/caddy.yml:
caddy_tls_mode: acme
caddy_tls_email: admin@example.com
caddy_https_port: 443
caddy_http_port: 80
```

### Custom ports (non-standard host)

```yaml
# In host_vars/server01/caddy.yml:
caddy_https_port: 8443
caddy_http_port: 8080
```

### Disable CA trust management

```yaml
# In host_vars/server01/caddy.yml:
caddy_manage_certs: false
caddy_manage_browser_trust: false
```

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/caddy.yml:
caddy_enabled: false
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| CA trust dir | `/etc/ca-certificates/trust-source/anchors/` | `/usr/local/share/ca-certificates/` | `/etc/pki/ca-trust/source/anchors/` | `/usr/share/ca-certificates/` | `/etc/ssl/certs/` |
| CA update cmd | `update-ca-trust` | `update-ca-certificates` | `update-ca-trust` | `update-ca-certificates` | `update-ca-certificates` |
| Docker | from `docker` role dependency | same | same | same | same |
| Config path | `/opt/caddy/Caddyfile` | same | same | same | same |
| Sites path | `/opt/caddy/sites/` | same | same | same | same |

## Logs

### Log sources

| Source | How to access | Contents |
|--------|--------------|----------|
| Caddy container | `docker logs caddy` | HTTP requests, TLS cert issuance, errors |
| Caddy access log | `docker logs caddy 2>&1 \| grep -i access` | Per-request HTTP access log |
| CA trust update | `journalctl -b \| grep -i ca` | CA certificate trust update events |
| Docker Compose | `docker compose -f /opt/caddy/docker-compose.yml logs` | Container lifecycle events |

Caddy writes structured JSON logs to stdout/stderr — captured by Docker. No file-based log rotation is configured for the container; Docker log rotation applies (configured in Docker daemon).

### Reading the logs

- **Check TLS cert issuance:** `docker logs caddy 2>&1 | grep -i "tls\|cert\|acme"`
- **Check reverse proxy errors:** `docker logs caddy 2>&1 | grep -i "error\|upstream\|dial"`
- **Check container is running:** `docker ps --filter name=caddy --filter status=running`
- **Validate Caddyfile manually:** `docker exec caddy caddy validate --config /etc/caddy/Caddyfile`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at OS assert | `ansible_facts['os_family']` not in supported list | Check `_caddy_supported_os` in defaults. Only Archlinux/Debian/RedHat/Void/Gentoo supported. |
| Container not starting | `docker logs caddy \| tail -50` | Port 80/443 already bound, missing proxy network, or bad Caddyfile syntax. Check `docker network ls`. |
| ACME cert fails | `docker logs caddy 2>&1 \| grep -i acme` | DNS not pointing to host, port 80 not reachable from internet, or `caddy_tls_email` missing. |
| CA certificate not trusted by browsers | `ls -la <trust_dir>/caddy-local.crt` | Cert not copied or `update-ca-trust` failed. Delete cert and re-run role. Some browsers (Chromium) require restart. |
| Backend service not reachable via Caddy | `docker network inspect proxy` | Service container must be on the `proxy` network. Verify `<service>_docker_network: proxy`. |
| Idempotence failure on Caddyfile | Two consecutive runs show `changed` | Template produces non-deterministic output. Check for missing `trim_blocks` or Jinja2 whitespace issues. |
| `caddy validate` fails inside container | `docker exec caddy caddy validate --config /etc/caddy/Caddyfile` | Invalid Caddyfile syntax after template change. Check Jinja2 rendering. |

## Testing

Two scenarios are required for every role. Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| `default` (localhost) | `molecule test -s default` | Smoke test: after changing templates or variables | Syntax, variable loading, directories, Caddyfile rendering |
| `docker` | `molecule test -s docker` | After changing task logic | Full converge + idempotence + verify on Arch + Ubuntu (config-only, no Docker daemon) |
| `vagrant` | `molecule test -s vagrant` | Before releasing or after OS-specific changes | Real Docker daemon, CA trust, container lifecycle, Arch + Ubuntu |

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all `ansible.builtin.assert` tasks pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|--------------------|
| Directories | `base_dir` 0755, `sites/` 0755, `data/` 0755, `config/` 0755, owned root:root | TEST-008 |
| Caddyfile | exists 0644, `# Ansible` managed header, `admin off`, `local_certs` (internal mode) | TEST-008 |
| docker-compose.yml | exists 0644, correct image, port mappings, volume mounts, proxy network | TEST-008 |
| Docker runtime | proxy network exists, container running, `caddy validate` passes, container on proxy network | TEST-008 |
| CA trust | root CA in OS trust dir, mode 0644 (internal TLS + Docker daemon only) | TEST-008 |
| Skip path | `caddy_enabled: false` runs without error | TEST-011 |

Verification categories skipped in Docker scenario: services (managed via docker compose, not init system), packages (role deploys via Docker image). Docker checks are skipped gracefully when Docker daemon is unavailable (molecule Docker scenario).

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `UNREACHABLE — docker` | Docker daemon not running on test host | Start Docker: `systemctl start docker` |
| `Assert base directory exists` fails | Directory creation failed (permission issue) | Check container runs as root; `become: true` is set |
| Idempotence: `Caddyfile changed` | Template produces non-deterministic output | Check for Jinja2 whitespace or undefined variable issues |
| `Assert caddy container is running` fails in docker scenario | Docker daemon not available in container (expected) | This assertion is guarded by `_caddy_verify_docker_info.rc == 0` — it should be skipped automatically |
| `Assert Caddyfile contains local_certs` fails | `caddy_tls_mode` not set to `internal` in converge vars | Ensure test uses `caddy_tls_mode: internal` (the default) |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `caddy` | Entire role | Full apply: `ansible-playbook workstation.yml --tags caddy` |
| `proxy` | Entire role (alias) | Same as `caddy` tag |
| `caddy,configure` | Directories, Caddyfile, docker-compose.yml, CA trust | Redeploy config without restarting: `ansible-playbook workstation.yml --tags caddy,configure` |
| `caddy,service` | `docker compose up` only | Restart service only: `ansible-playbook workstation.yml --tags caddy,service` |
| `caddy,report` | Execution report only | Re-generate report: `ansible-playbook workstation.yml --tags caddy,report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No — override via inventory |
| `vars/main.yml` | CA cert filename | Only when renaming cert |
| `vars/<os_family>.yml` | CA trust dir, update command, browser policy dir per distro | Only when adding distro support |
| `templates/Caddyfile.j2` | Global Caddy config template | When changing TLS or global directives |
| `templates/docker-compose.yml.j2` | Container definition template | When changing container config |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/validate.yml` | OS and variable validation | When adding validation rules |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `handlers/main.yml` | restart/reload handlers | Rarely |
| `molecule/default/` | Localhost smoke test | When changing smoke test coverage |
| `molecule/docker/` | Docker containerized test | When changing Docker test coverage |
| `molecule/vagrant/` | Full VM test | When changing multi-distro coverage |
| `molecule/shared/converge.yml` | Shared converge playbook | When changing test variables |
| `molecule/shared/verify.yml` | Shared verify playbook | When adding verification assertions |
| `requirements.yml` | Role dependencies (common, docker) | When adding role dependencies |
| `meta/main.yml` | Role metadata and galaxy dependencies | Rarely |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
