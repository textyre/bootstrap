# Claudette Agent Memory - Bootstrap Project

## Project Structure
- Ansible roles at `ansible/roles/`
- Docker role is the base pattern for all container-based roles
- Molecule tests use `default` driver with localhost, vault password from `vault-pass.sh`
- All remote execution via SSH scripts (`scripts/ssh-run.sh`, `scripts/ssh-scp-to.sh`)

## Ansible Role Patterns
- Comments in Russian, section headers: `# ---- Описание ----`
- Top-of-file header: `# === Название роли ===`
- Variable prefix matches role name: `docker_*`, `caddy_*`
- Tags: role name + functional tags like `configure`, `service`
- FQCN for all modules: `ansible.builtin.file`, `community.docker.docker_network`
- Handlers use `listen:` for cross-role notification
- meta/main.yml: `dependencies:` as list (not `[]` unless empty)
- molecule/default/molecule.yml: exact copy pattern from docker role
- verify.yml: `_rolename_verify_*` register variable naming convention

## Caddy Role (created 2026-02-09)
- Reverse proxy for all self-hosted services
- Depends on docker role
- TLS modes: "internal" (self-signed) or "acme" (Let's Encrypt)
- Docker network "proxy" for service connectivity
- Site configs imported from `/etc/caddy/sites/*.caddy`
