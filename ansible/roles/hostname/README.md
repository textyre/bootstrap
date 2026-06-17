# hostname

Sets the system hostname and manages the `127.0.1.1` entry in `/etc/hosts`.

## What this role does

- [x] Asserts OS family is supported (ROLE-003 preflight)
- [x] Validates `hostname_name` (required, RFC-compliant regex check)
- [x] Validates `hostname_domain` when provided
- [x] Sets hostname via `ansible.builtin.hostname` with OS-appropriate strategy
- [x] Manages `127.0.1.1` line in `/etc/hosts` (FQDN optional)
- [x] Verifies hostname via python3 socket (cross-platform, ROLE-002)
- [x] Verifies `/etc/hostname` content matches expected value
- [x] Verifies `/etc/hosts` entry via ansible-native lineinfile check (ROLE-011)
- [x] Reports each phase via the `common` role

## Execution order

```
validate -> hostname -> hosts -> final report
```

`tasks/main.yml` is only the top-level phase router. `tasks/hostname.yml`
and `tasks/hosts.yml` own their internal configure -> verify -> report flow.
Public inputs live in `defaults/main.yml`; role-wide internal mappings live in
`vars/main.yml`.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `hostname_name` | `""` | **Required.** Static hostname. Must match `^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$` |
| `hostname_domain` | `""` | Optional DNS domain suffix. If set, inserts `127.0.1.1 host.domain host`; otherwise `127.0.1.1 host` |

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
127.0.1.1 archbox.example.com archbox
```

Without `hostname_domain`:

```yaml
hostname_name: "archbox"
```

```
127.0.1.1 archbox
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
| default | localhost | Syntax check, converge, idempotence, and localhost preservation check |
| docker | Arch + Ubuntu (systemd) | Full cycle with Docker containers: role runtime verify, idempotence, localhost preserved |
| vagrant | Arch + Ubuntu (KVM) | Full cycle on real VMs: same checks as docker but with kernel-level hostname operations |

**Edge cases tested:**
- Invalid `hostname_name` (negative test: role rejects `-invalid-` via assert)
- Role-level verify covers hostname, `/etc/hostname`, expected `/etc/hosts` entry, and duplicate `127.0.1.1` detection
- Molecule verify only covers localhost preservation outside the role's direct postconditions
