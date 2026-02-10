---
name: self-hosted
description: Reference patterns for creating Ansible roles that deploy self-hosted services behind Caddy reverse proxy with Docker.
---

# Self-Hosted Service Patterns

Reference document for creating Ansible roles that deploy containerized services behind Caddy reverse proxy.

## Architecture pattern (Caddy + Docker)

Every self-hosted service follows this pattern:

- Service runs in Docker, connected to shared network `proxy` (external, created by caddy role)
- Service does NOT expose ports to host — only accessible through Caddy reverse proxy
- Service drops its `.caddy` site config into `/opt/caddy/sites/` → notify Reload caddy
- `/etc/hosts` entry automated via `lineinfile` in the role (for `*.local` domains)
- All "manual steps after deploy" must be automated — nothing left for the user to do

## TLS trust chain (when using `tls internal`)

MUST be automated in the caddy role — not left as manual steps:

- [ ] CA cert copied from container: `docker cp caddy:/data/caddy/pki/authorities/local/root.crt`
- [ ] File permissions fixed to `0644` (docker cp creates `0600`, unreadable by browser user)
- [ ] System trust store updated: `update-ca-trust` (Arch) or `update-ca-certificates` (Debian)
- [ ] Firefox/Zen Browser: `policies.json` with `ImportEnterpriseRoots: true` in distribution dir
- [ ] Chrome/Chromium: uses system store automatically (no extra step needed)

## Secret generation

When a role needs a secret (token, password, key):

- [ ] Generate automatically on first deploy (e.g. `openssl rand -base64 48`)
- [ ] Store on the server in a restricted file (mode `0600`, owner root)
- [ ] Use `creates:` parameter to skip generation on subsequent runs
- [ ] Read via `slurp` + `set_fact` for use in templates
- [ ] Template uses `{{ _generated_var | default(vault_var) }}` — server-generated takes precedence, vault.yml is fallback

## New service role checklist

When creating a role for a new self-hosted service, verify ALL items:

- [ ] Docker network `proxy` used (not a new network)
- [ ] No ports exposed to host
- [ ] Caddy site config in `/opt/caddy/sites/<service>.caddy`
- [ ] `/etc/hosts` entry for `<service>.local`
- [ ] Secrets generated automatically (see above)
- [ ] TLS trust chain handled by caddy role (see above)
- [ ] Reload caddy handler triggered after config drop
- [ ] Backup strategy defined (if service has persistent data)
