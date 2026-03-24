# hostname role

Sets the system hostname and manages the `127.0.1.1` entry in `/etc/hosts`.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `hostname_name` | `""` | **Required.** Static hostname (RFC 952/1123 compliant) |
| `hostname_domain` | `""` | Optional FQDN suffix. Produces `127.0.1.1 host.domain host` when set |

## Internal variables

| Variable | Source | Description |
|----------|--------|-------------|
| `_hostname_supported_os` | `defaults/main.yml` | Supported OS families: Archlinux, Debian, RedHat, Void, Gentoo |
| `_hostname_strategy` | `vars/{os_family}.yml` | Ansible hostname module strategy per OS family |

## Tags

| Tag | Scope |
|-----|-------|
| `hostname` | All tasks |
| `report` | Reporting tasks only |

## Dependencies

- `common` role (for `report_phase.yml` and `report_render.yml`)

## Execution flow

1. **Preflight** — assert OS family is supported (ROLE-003)
2. **Load vars** — include OS-specific vars for hostname strategy (ROLE-001)
3. **Validate** — assert `hostname_name` is defined and RFC-compliant
4. **Set hostname** — `ansible.builtin.hostname` with per-OS strategy
5. **Configure /etc/hosts** — manage `127.0.1.1` line with optional FQDN
6. **Verify** — python3 socket hostname check + `/etc/hostname` content check (ROLE-005)
7. **Report** — execution report via `common` role (ROLE-008)

## Platform support

| OS Family | Strategy | Init systems |
|-----------|----------|-------------|
| Archlinux | `systemd` | systemd |
| Debian | `debian` | systemd |
| RedHat | `redhat` | systemd |
| Void | `generic` | runit |
| Gentoo | `generic` | openrc |
