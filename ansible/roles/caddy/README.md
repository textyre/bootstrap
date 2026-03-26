# caddy

Deploys [Caddy](https://caddyserver.com/) as a Dockerized HTTPS reverse proxy for all self-hosted services.

## What this role does

- [x] Validates inputs and asserts supported OS (preflight)
- [x] Creates a Docker network for inter-service communication (`caddy_docker_network`)
- [x] Creates base directory structure (`/opt/caddy`, `sites/`, `data/`, `config/`)
- [x] Deploys `Caddyfile` from Jinja2 template (with `admin off`, optional `local_certs`)
- [x] Deploys `docker-compose.yml` from Jinja2 template
- [x] Starts the Caddy container via `docker compose`
- [x] Copies Caddy's internal root CA into the system trust store (internal TLS only, multi-distro)
- [x] Updates system CA trust (distro-specific command)
- [x] Configures Zen Browser to import enterprise roots (internal TLS only, best-effort)
- [x] Verifies deployment (config files, container status, Caddyfile syntax)
- [x] Reports execution phases via `common/report_phase.yml`

## Execution Flow

```
validate.yml -> Network -> Directories -> Config -> Service -> CA trust -> Browser trust -> verify.yml -> Report
```

## Requirements

- Docker daemon running on the target host
- `community.docker` collection installed (`ansible-galaxy collection install community.docker`)
- The `docker` role applied before this role (see Dependencies)

## Supported Platforms

| Distro | OS Family | CA Trust Command |
|--------|-----------|-----------------|
| Arch Linux | Archlinux | `update-ca-trust` |
| Ubuntu | Debian | `update-ca-certificates` |
| Fedora | RedHat | `update-ca-trust` |
| Void Linux | Void | `update-ca-certificates` |
| Gentoo | Gentoo | `update-ca-certificates` |

## Role variables

| Variable | Default | Description |
|----------|---------|-------------|
| `caddy_enabled` | `true` | Enable/disable the entire role |
| `caddy_base_dir` | `/opt/caddy` | Base directory for all Caddy files |
| `caddy_https_port` | `443` | Host port mapped to container HTTPS (443) |
| `caddy_http_port` | `80` | Host port mapped to container HTTP (80) |
| `caddy_tls_mode` | `internal` | TLS mode: `internal` (self-signed CA) or `acme` (Let's Encrypt) |
| `caddy_tls_email` | `""` | Email for Let's Encrypt (required when `caddy_tls_mode: acme`) |
| `caddy_docker_network` | `proxy` | Docker network name shared with backend services |
| `caddy_docker_image` | `caddy:2-alpine` | Docker image for Caddy container |
| `caddy_manage_network` | `true` | Manage Docker network creation |
| `caddy_manage_certs` | `true` | Manage CA certificate trust (internal TLS only) |
| `caddy_manage_browser_trust` | `true` | Manage browser enterprise root trust (internal TLS only) |

### TLS modes

- **`internal`** -- Caddy generates a local CA and issues self-signed certificates. The CA is copied into the system trust store (OS-specific path) and Zen Browser policy. No internet access required.
- **`acme`** -- Caddy requests certificates from Let's Encrypt via ACME. Requires `caddy_tls_email` and public DNS pointing to the host.

### Per-subsystem toggles

Each major subsystem can be independently disabled:

- `caddy_manage_network` -- skip Docker network creation (if managed elsewhere)
- `caddy_manage_certs` -- skip CA certificate trust deployment
- `caddy_manage_browser_trust` -- skip Zen Browser enterprise root policy

## Cross-platform notes

CA trust store paths and update commands are OS-specific. The role uses `vars/main.yml` mappings keyed by `ansible_facts['os_family']` to resolve the correct paths automatically.

## Dependencies

- `docker` -- this role must run before `caddy` (declared in `meta/main.yml`)

## Example playbook

```yaml
- hosts: workstation
  become: true
  roles:
    - role: docker
    - role: caddy
      vars:
        caddy_tls_mode: internal
        caddy_docker_network: proxy
```

To use ACME (Let's Encrypt):

```yaml
- hosts: workstation
  become: true
  roles:
    - role: caddy
      vars:
        caddy_tls_mode: acme
        caddy_tls_email: admin@example.com
```

## Tags

| Tag | Description |
|-----|-------------|
| `caddy` | All tasks |
| `proxy` | All tasks (alias) |
| `caddy,configure` | Directory creation, template deployment, CA trust |
| `caddy,service` | `docker compose up` only |
| `caddy,report` | Execution report only |

## File Map

```
caddy/
  defaults/main.yml    -- Public API: all configurable variables
  vars/main.yml        -- Internal: OS-specific CA paths, browser policy dirs
  tasks/
    main.yml           -- Router: validate -> configure -> service -> verify -> report
    validate.yml       -- Preflight: OS assert, TLS mode, email
    verify.yml         -- Post-deploy: config check, container status, syntax
  handlers/main.yml    -- Restart/reload via docker compose / docker exec
  templates/
    Caddyfile.j2       -- Global Caddy config
    docker-compose.yml.j2 -- Container definition
  meta/main.yml        -- Role metadata, docker dependency
  molecule/
    default/           -- Localhost scenario (real Docker daemon)
    docker/            -- Arch + Ubuntu container (config-only, no daemon)
    vagrant/           -- Arch + Ubuntu VM (full integration)
    shared/            -- Shared converge.yml and verify.yml
```

## Troubleshooting

### Caddy container not starting

Check Docker logs: `docker logs caddy`. Most common cause is port conflict on 80/443.

### CA certificate not trusted

Verify the cert was copied: `ls -la <trust_dir>/caddy-local.crt`. Run the update command manually to check for errors.

### Idempotence failures

The `docker cp` command for CA extraction does not have native idempotency tracking. The role marks this as `changed_when: false` since the file content is deterministic from the container's PKI.

## Testing

Molecule tests live in `molecule/`. Three scenarios are provided:

### `default` (localhost, no container)

Runs against `localhost` using a local Ansible connection. Requires the actual system to have Docker installed.

```bash
cd ansible/roles/caddy
molecule test -s default
```

### `docker` (Arch + Ubuntu systemd container)

Runs inside privileged containers with systemd. Config-only verification (no Docker daemon available inside containers).

```bash
cd ansible/roles/caddy
molecule test -s docker
```

### `vagrant` (Arch + Ubuntu VM)

Full integration test with real Docker daemon, CA trust, and container lifecycle.

```bash
cd ansible/roles/caddy
molecule test -s vagrant
```

### Shared verify playbook

Both scenarios share `molecule/shared/verify.yml`, which asserts:

1. **Directory structure** -- `caddy_base_dir` and subdirectories exist with `root:root 0755`
2. **Caddyfile** -- exists, `root:root 0644`, contains `Ansible` managed marker, `admin off`, correct TLS directive
3. **docker-compose.yml** -- exists, `root:root 0644`, references correct image, port mappings, volume mounts, and proxy network
4. **Docker daemon checks** (skipped gracefully when daemon unavailable):
   - Proxy Docker network exists
   - Caddy container is running
   - `caddy validate` passes inside the container
   - Container is connected to proxy network
5. **CA trust** (internal TLS + Docker daemon only) -- root CA file present in OS-specific trust directory
