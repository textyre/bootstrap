# caddy

Deploys [Caddy](https://caddyserver.com/) as a Dockerized HTTPS reverse proxy for all self-hosted services.

## What this role does

- [x] Creates a Docker network for inter-service communication (`caddy_docker_network`)
- [x] Creates base directory structure (`/opt/caddy`, `sites/`, `data/`, `config/`)
- [x] Deploys `Caddyfile` from Jinja2 template (with `admin off`, optional `local_certs`)
- [x] Deploys `docker-compose.yml` from Jinja2 template
- [x] Starts the Caddy container via `docker compose`
- [x] Copies Caddy's internal root CA into the Arch system trust store (internal TLS only)
- [x] Updates system CA trust (`update-ca-trust`)
- [x] Configures Zen Browser to import enterprise roots (internal TLS only, best-effort)

## Requirements

- Docker daemon running on the target host
- `community.docker` collection installed (`ansible-galaxy collection install community.docker`)
- The `docker` role applied before this role (see Dependencies)

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

### TLS modes

- **`internal`** — Caddy generates a local CA and issues self-signed certificates. The CA is copied into the Arch system trust store and Zen Browser policy. No internet access required.
- **`acme`** — Caddy requests certificates from Let's Encrypt via ACME. Requires `caddy_tls_email` and public DNS pointing to the host.

## Dependencies

- `docker` — this role must run before `caddy` (declared in `meta/main.yml`)

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

## Testing

Molecule tests live in `molecule/`. Two scenarios are provided:

### `default` (localhost, no container)

Runs against `localhost` using a local Ansible connection. Requires the actual system to have Docker installed.

```bash
cd ansible/roles/caddy
molecule test -s default
```

### `docker` (Arch Linux systemd container)

Runs inside a privileged Arch Linux container with systemd. Requires the custom image (`ghcr.io/textyre/arch-base:latest`) and a running Docker daemon with cgroup v2 support.

```bash
cd ansible/roles/caddy
molecule test -s docker
```

Or from the repository root:

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible && source .venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg molecule test -s docker --scenario-path roles/caddy/molecule/docker"
```

### Shared verify playbook

Both scenarios share `molecule/shared/verify.yml`, which asserts:

1. **Directory structure** — `caddy_base_dir` and subdirectories (`sites/`, `data/`, `config/`) exist with `root:root 0755`
2. **Caddyfile** — exists, `root:root 0644`, contains `Ansible` managed marker, `admin off`, correct TLS directive
3. **docker-compose.yml** — exists, `root:root 0644`, references correct image (`caddy:2-alpine`), port mappings, volume mounts, and proxy network
4. **Docker daemon checks** (skipped gracefully when daemon unavailable):
   - Proxy Docker network exists
   - Caddy container is running
   - `caddy validate` passes inside the container
   - Container is connected to proxy network
5. **CA trust** (Arch Linux + internal TLS + Docker daemon only) — root CA file present at `/etc/ca-certificates/trust-source/anchors/caddy-local.crt` with `0644`
