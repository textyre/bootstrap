# hostname

Sets the system hostname and manages the `127.0.1.1` entry in `/etc/hosts`.

## What this role does

- [x] Validates `hostname_name` (required, RFC-compliant regex check)
- [x] Sets hostname via `ansible.builtin.hostname` with OS-appropriate strategy
- [x] Manages `127.0.1.1` line in `/etc/hosts` (FQDN optional)
- [x] Verifies hostname matches expected value after change
- [x] Verifies `/etc/hosts` contains the new hostname
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
| Alpine | `alpine` |
| Void Linux | `generic` |

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

### Docker scenario (Arch + systemd, requires Docker)

```bash
molecule test -s docker
```

### Vagrant scenario (Arch + Ubuntu Noble, requires KVM/libvirt)

```bash
molecule test -s vagrant
```

The vagrant scenario tests both `generic/arch` and `ubuntu-base` VMs
against the same `shared/converge.yml` and `shared/verify.yml`.

### Test sequence

`syntax → create → prepare → converge → idempotence → verify → destroy`

All four verify checks are OS-agnostic:

1. `hostnamectl status --static` matches expected hostname
2. `/etc/hosts` contains `127.0.1.1`, FQDN, and short name
3. Exactly one `127.0.1.1` line (no duplicates)
4. Summary debug output
