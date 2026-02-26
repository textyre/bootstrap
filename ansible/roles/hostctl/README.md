# hostctl

Installs the [hostctl](https://github.com/guumaster/hostctl) CLI tool and manages
`/etc/hosts` profiles. hostctl enables multiple named profiles with enable/disable
semantics without manual editing of `/etc/hosts`.

## Requirements

- Ansible 2.15+
- `become: true` (root access required)
- Outbound HTTPS access to `api.github.com` and `github.com` (for GitHub releases fallback)

## Supported distributions

Arch Linux, Ubuntu, Fedora, Void Linux, Gentoo.

## Installation strategy

The role uses a three-tier fallback:

1. **Package manager** (`ansible.builtin.package`) — for non-Arch systems. Fails
   silently if no system package is available (no official apt/dnf repo exists upstream).
2. **AUR** (`kewlfft.aur.aur: hostctl-bin`) — for Arch Linux via `yay`.
3. **GitHub releases** — downloads the Linux tarball, optionally verifies SHA256
   checksum, extracts binary to `hostctl_install_dir`. Used as fallback when tiers
   1 and 2 produce nothing.

On Ubuntu, tiers 1 and 2 are skipped (no apt repo, not Arch); tier 3 is the active path.
On Arch, tier 2 runs first; tier 3 fires only if `yay` is absent or AUR install fails.

## Role variables

| Variable | Default | Description |
|---|---|---|
| `hostctl_enabled` | `true` | Guard — role is a no-op when `false` |
| `hostctl_version` | `"latest"` | Version to install. `"latest"` resolves via GitHub API; pin to e.g. `"1.1.4"` for reproducibility |
| `hostctl_install_dir` | `/usr/local/bin` | Directory the binary is placed into |
| `hostctl_github_repo` | `"guumaster/hostctl"` | GitHub repository for release downloads |
| `hostctl_github_api` | `"https://api.github.com"` | GitHub API base URL |
| `hostctl_verify_checksum` | `true` | Verify SHA256 checksum of the downloaded tarball |
| `hostctl_profiles` | `{}` | Map of profile name → list of `{ip, host}` entries |

### Profile format

```yaml
hostctl_profiles:
  dev:
    - { ip: "127.0.0.1", host: "app.local" }
    - { ip: "127.0.0.1", host: "api.local" }
  registry:
    - { ip: "172.17.0.1", host: "registry.local" }
```

Each profile is deployed as `/etc/hostctl/<name>.hosts` and applied to `/etc/hosts`
via `hostctl add domains`. The handler re-applies profiles on every change: it runs
`hostctl remove <profile>` first to ensure idempotency.

## Example playbook

```yaml
- name: Configure /etc/hosts profiles
  hosts: workstations
  become: true
  roles:
    - role: hostctl
      vars:
        hostctl_version: "1.1.4"
        hostctl_verify_checksum: true
        hostctl_profiles:
          dev:
            - { ip: "127.0.0.1", host: "app.local" }
            - { ip: "127.0.0.1", host: "api.local" }
```

## Notes

- **GitHub rate limits**: When `hostctl_version: "latest"`, the role queries the
  GitHub API on every run. The unauthenticated limit is 60 req/hr per IP. Pin the
  version in any environment that runs the role frequently or in CI.
- **AUR path and binary location**: The `hostctl-bin` AUR package installs to
  `/usr/bin/hostctl`, not `/usr/local/bin/hostctl`. If AUR succeeds, the GitHub
  fallback is skipped and the binary lands outside `hostctl_install_dir`. The docker
  molecule scenario tests the AUR path; the vagrant scenario skips AUR to keep
  the binary path predictable.
- **Idempotency**: The role checks for the installed version before attempting any
  install. If the pinned version is already present, all install tasks are skipped.

## Testing

### Molecule scenarios

| Scenario | Driver | Platforms | Notes |
|---|---|---|---|
| `default` | localhost | host system | Runs on local machine, no container/VM |
| `docker` | Docker | Arch systemd container | Tests AUR path; custom image with systemd |
| `vagrant` | Vagrant/KVM | Arch VM + Ubuntu Noble VM | Tests GitHub download fallback on both platforms |

Run locally (requires molecule and the appropriate driver):

```bash
cd ansible/roles/hostctl

# Docker scenario (fast, Arch only, tests AUR path)
molecule test -s docker

# Vagrant scenario (cross-platform, requires libvirt)
molecule test -s vagrant

# Syntax check only
molecule syntax -s vagrant
```

## License

MIT
