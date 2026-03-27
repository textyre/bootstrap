# hostname

Sets the system hostname and manages the `127.0.1.1` entry in `/etc/hosts`.

## What this role does

- [x] Asserts OS family is supported (ROLE-003 preflight)
- [x] Validates `hostname_name` (required, RFC-compliant regex check)
- [x] Sets hostname via `ansible.builtin.hostname` with OS-appropriate strategy
- [x] Manages `127.0.1.1` line in `/etc/hosts` (FQDN optional)
- [x] Verifies hostname via python3 socket (cross-platform, ROLE-002)
- [x] Verifies `/etc/hostname` content matches expected value
- [x] Verifies `/etc/hosts` entry via ansible-native lineinfile check (ROLE-011)
- [x] Reports each phase via the `common` role

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `hostname_name` | `""` | **Required.** Static hostname. Must match `^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$` |
| `hostname_domain` | `""` | Optional FQDN suffix. If set, inserts `127.0.1.1 host.domain\thost`; otherwise `127.0.1.1 host` |

## Supported platforms

| OS Family | Hostname strategy |
|-----------|------------------|
| Arch Linux | `systemd` |
| Debian / Ubuntu | `debian` |
| RedHat / Fedora | `redhat` |
| Void Linux | `generic` |
| Gentoo | `generic` |

## Tags

| Tag | Runs |
|-----|------|
| `hostname` | All tasks |
| `report` | Reporting tasks only (`common` role) |

Skip reporting in automated pipelines: `--skip-tags report`

## Example

```yaml
- hosts: workstations
  become: true
  roles:
    - role: hostname
      vars:
        hostname_name: "archbox"
        hostname_domain: "example.com"
```

Resulting `/etc/hosts` entry:

```
127.0.1.1	archbox.example.com	archbox
```

Without `hostname_domain`:

```yaml
hostname_name: "archbox"
```

```
127.0.1.1	archbox
```

## Testing

### Default scenario (localhost)

```bash
molecule test
```

### Docker scenario (Arch + Ubuntu systemd, requires Docker)

```bash
molecule test -s docker
```

### Vagrant scenario (Arch + Ubuntu, requires KVM/libvirt)

```bash
molecule test -s vagrant
```

The vagrant scenario tests both `arch-base` and `ubuntu-base` VMs
against the same `shared/converge.yml` and `shared/verify.yml`.

### Test sequence

`syntax → create → prepare → converge → idempotence → verify → destroy`

### Test coverage

| Scenario | Platforms | What is tested |
|----------|-----------|----------------|
| default | localhost | Syntax check, converge + idempotence, verify — hostname + /etc/hosts with FQDN |
| docker | Arch + Ubuntu (systemd) | Full cycle with Docker containers: hostname set, /etc/hosts managed, FQDN entry, no duplicates, localhost preserved |
| vagrant | Arch + Ubuntu (KVM) | Full cycle on real VMs: same checks as docker but with kernel-level hostname operations |

**Edge cases tested:**
- Invalid `hostname_name` (negative test: role rejects `-invalid-` via assert)
- Verify checks are data-driven via `extra-vars` (no hardcoded values in verify.yml)
- Both with-domain and no-domain paths covered in verify.yml logic
