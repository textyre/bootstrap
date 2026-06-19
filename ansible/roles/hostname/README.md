# hostname

Sets the system hostname. `/etc/hosts` is owned by the `hostctl` role.

## What this role does

- [x] Asserts OS family is supported (ROLE-003 preflight)
- [x] Validates `hostname_name` (required, RFC-compliant regex check)
- [x] Validates `hostname_domain` when provided
- [x] Sets hostname via `ansible.builtin.hostname` with OS-appropriate strategy
- [x] Verifies hostname via python3 socket (cross-platform, ROLE-002)
- [x] Verifies `/etc/hostname` content matches expected value
- [x] Reports each phase via the `common` role

## Execution order

```
validate -> hostname -> final report
```

`tasks/main.yml` is only the top-level phase router. `tasks/hostname.yml`
owns its internal configure -> verify -> report flow. Public inputs live in
`defaults/main.yml`; role-wide internal mappings live in `vars/main.yml`.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `hostname_name` | `""` | **Required.** Static hostname. Must match `^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$` |
| `hostname_domain` | `""` | Optional DNS domain suffix used by the hostname role |

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

Without `hostname_domain`:

```yaml
hostname_name: "archbox"
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
| default | localhost | Syntax check, converge, and idempotence |
| docker | Arch + Ubuntu (systemd) | Full cycle with Docker containers: role runtime verify and idempotence |
| vagrant | Arch + Ubuntu (KVM) | Full cycle on real VMs: same checks as docker but with kernel-level hostname operations |

**Edge cases tested:**
- Invalid `hostname_name` (negative test: role rejects `-invalid-` via assert)
- Role-level verify covers hostname and `/etc/hostname`
- `/etc/hosts` ownership is tested by the `hostctl` role
