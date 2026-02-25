# ssh_keys

SSH authorized_keys deployment and optional keypair generation, extracted from the user role for single-responsibility.

## What this role does

- [x] Deploys SSH `authorized_keys` from `accounts[].ssh_keys` data source
- [x] Removes `authorized_keys` for absent users (zero-trust cleanup)
- [x] Optionally generates SSH keypairs (ed25519 by default) on target machines via `community.crypto.openssh_keypair`
- [x] Verifies `.ssh` directory permissions (0700) and `authorized_keys` existence for each present user
- [x] Backward compatible: falls back to `user_owner` + `user_additional_users` if `accounts` is not defined

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_keys_manage_authorized_keys` | `true` | Deploy `authorized_keys` from the `accounts` data source |
| `ssh_keys_generate_user_keys` | `false` | Generate SSH keypairs on target machines |
| `ssh_keys_key_type` | `ed25519` | Key type for generation: `ed25519`, `rsa`, or `ecdsa` |
| `ssh_keys_exclusive` | `false` | Remove keys not listed in `accounts[].ssh_keys` from `authorized_keys` |

## Data source

The role reads user and key data from the shared `accounts` variable (same source used by the `user` role):

```yaml
accounts:
  - name: alice
    state: present
    ssh_keys:
      - "ssh-ed25519 AAAA... alice@laptop"
      - "ssh-ed25519 AAAA... alice@phone"
  - name: bob
    state: absent   # authorized_keys will be removed
```

When `accounts` is not defined, the role falls back to `user_owner` and `user_additional_users` for backward compatibility with existing playbooks.

## Dependencies

Declared in `ansible/requirements.yml`:

- `ansible.posix` — `authorized_key` module
- `community.crypto` — `openssh_keypair` module (required only when `ssh_keys_generate_user_keys: true`)

The `user` role must run before `ssh_keys` to ensure user home directories exist.

## Supported platforms

Arch Linux, Debian/Ubuntu, RedHat/EL, Void Linux, Gentoo

## Testing

The role has three molecule scenarios sharing a common `converge.yml` and `verify.yml` in `molecule/shared/`.

### Scenarios

| Scenario | Driver | Platforms | Purpose |
|----------|--------|-----------|---------|
| `default` | localhost | macOS/Linux (local) | Fast local syntax and idempotency check |
| `docker` | Docker | `arch-systemd` container | CI integration, Arch Linux |
| `vagrant` | Vagrant (libvirt) | Arch + Ubuntu 24.04 VMs | Multi-distro validation |

### What is tested

| Check | Assertion |
|-------|-----------|
| `.ssh` directory exists | `stat.exists == true`, `isdir == true` |
| `.ssh` directory mode | `mode == '0700'` |
| `.ssh` directory owner | `pw_name == testuser` |
| `authorized_keys` exists | `stat.exists == true`, `isreg == true` |
| `authorized_keys` mode | `mode == '0600'` |
| `authorized_keys` owner | `pw_name == testuser` |
| First key content | `'test@molecule' in file` |
| Second key content | `'test2@molecule' in file` |
| Absent user cleanup | `authorized_keys` removed for `state: absent` user |

### Running

```bash
# Local (no containers required)
cd ansible/roles/ssh_keys
molecule test

# Docker (Arch Linux container)
molecule test -s docker

# Vagrant (Arch + Ubuntu VMs, requires KVM/libvirt)
molecule test -s vagrant
```

## Tags

| Tag | Purpose |
|-----|---------|
| `ssh_keys` | All tasks |
| `ssh_keys`, `security` | Authorized keys deployment only |
| `ssh_keys`, `report` | Execution report |

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
