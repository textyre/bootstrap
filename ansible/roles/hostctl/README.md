# hostctl

Installs the [hostctl](https://github.com/guumaster/hostctl) CLI from GitHub
releases and manages named `/etc/hosts` profiles.

## What this role does

- [x] Validates supported OS family and CPU architecture before mutation
- [x] Validates public role inputs and profile shape
- [x] Installs `hostctl` into `hostctl_install_dir`
- [x] Verifies the installed binary and pinned version when applicable
- [x] Owns `/etc/hosts` from role variables
- [x] Manages enabled hostctl profiles
- [x] Verifies enabled profile status through `hostctl`

## Execution order

```text
validate -> install binary -> verify binary -> profiles
```

`tasks/main.yml` is only the top-level phase router. The install phase owns
the idempotency precheck and GitHub release installation method, while binary
verification asserts the installed command contract. The profiles phase owns
configure plus profile verification. Molecule tests do not repeat role
postconditions.

## Variables

| Variable | Default | Description |
|---|---|---|
| `hostctl_enabled` | `true` | Skips the role when `false` |
| `hostctl_version` | `"latest"` | Version to install. `"latest"` accepts any installed version unless `hostctl_force_update` is `true`; pin to a hostctl version such as `"1.1.4"` for reproducibility |
| `hostctl_force_update` | `false` | Re-download when `hostctl_version: "latest"` is already installed |
| `hostctl_install_dir` | `/usr/local/bin` | Directory where the binary is installed |
| `hostctl_verify_checksum` | `true` | Require release checksum verification |
| `hostctl_hosts_entries` | `[]` | Required base `/etc/hosts` rows managed before hostctl profile sections, including hostname rows such as `127.0.1.1` when needed |
| `hostctl_profiles` | `{}` | Map of profile name to entries |

## Profile Format

```yaml
hostctl_profiles:
  dev:
    entries:
      - { ip: "127.0.0.1", host: "app.local" }
      - { ip: "127.0.0.1", host: "api.local" }
```

Each profile is rendered as an enabled hostctl section in `/etc/hosts`.

## Hosts Ownership

The role renders `/etc/hosts` as a complete file. This is intentional: clean
systems are configured from scratch, repeated runs are idempotent, and dirty
systems are converged back to playbook variables instead of accumulating stale
blocks.

The rendered file contains:

- `hostctl_hosts_entries`
- enabled `hostctl_profiles` sections in hostctl's native marker format

## Supported Platforms

The role is scoped to the project OS families: Archlinux, Debian, RedHat, Void,
and Gentoo. GitHub release assets are supported for `x86_64`, `aarch64`, and
`armv7l`.

## Testing

Molecule scenarios run syntax, converge, idempotence, and verify. Role-level
verify covers the binary and hostctl profile state.
Molecule verify only checks that the base `127.0.0.1 localhost` entry is still
preserved.

| Scenario | Driver | Platforms |
|---|---|---|
| `default` | localhost | host system |
| `docker` | Docker | Arch systemd and Ubuntu systemd containers |
| `vagrant` | Vagrant/KVM | Arch VM and Ubuntu VM |

```bash
molecule test -s docker
molecule test -s vagrant
molecule syntax -s vagrant
```
