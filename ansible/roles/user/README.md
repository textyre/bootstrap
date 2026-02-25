# user

Manages the full user-account lifecycle on workstations: primary owner, additional users, sudo policy, umask hardening, and sudo audit log rotation.

## What this role does

- [x] Installs the `sudo` package (package name mapped per OS family)
- [x] Creates and configures the primary **owner** user (shell, groups, umask, optional password aging)
- [x] Creates and configures **additional users** with per-user sudo membership and umask
- [x] Removes users with `state: absent` from the `accounts` list (zero-trust cleanup)
- [x] Deploys `/etc/sudoers.d/<group>` via Jinja2 template with CIS 5.3.x controls
- [x] Deploys `/etc/logrotate.d/sudo` for sudo audit log retention (CIS minimum 90 days)
- [x] Deploys `/etc/profile.d/umask-<user>.sh` for per-user login umask (CIS 5.4.2)
- [x] Optionally verifies root account is locked (`CIS 5.4.3`)
- [x] In-role post-run verification via `tasks/verify.yml`
- [x] Dual-format execution report (console + JSON) via `common` role

## Variables

### Owner

| Variable | Default | Description |
|----------|---------|-------------|
| `user_owner.name` | `$SUDO_USER` or current user | Primary admin username |
| `user_owner.shell` | `/bin/bash` | Login shell |
| `user_owner.groups` | `[user_sudo_group]` | Additional groups |
| `user_owner.password_hash` | `""` | Pre-hashed SHA-512 password (empty = account locked) |
| `user_owner.update_password` | `on_create` | When to update password (`always`/`on_create`) |
| `user_owner.umask` | `"027"` | CIS 5.4.2 restrictive umask |
| `user_owner.password_max_age` | `365` | CIS 5.5.1: days before password must change |
| `user_owner.password_min_age` | `1` | CIS 5.5.2: days before password can change |
| `user_owner.password_warn_age` | `7` | Days before expiry to warn |

### Additional users

| Variable | Default | Description |
|----------|---------|-------------|
| `user_additional_users` | `[]` | List of user dicts (same fields as `user_owner`, plus `sudo: bool`) |

### Feature toggles

| Variable | Default | Description |
|----------|---------|-------------|
| `user_manage_password_aging` | `true` | Set `password_expire_max/min` via `chage` |
| `user_manage_umask` | `true` | Deploy `/etc/profile.d/umask-<user>.sh` |
| `user_verify_root_lock` | `true` | CIS 5.4.3: assert root has no direct password login |

### Sudo policy

| Variable | Default | Description |
|----------|---------|-------------|
| `user_sudo_group` | `wheel` (Arch) / `sudo` (Debian) | Sudo group name — auto-detected |
| `user_sudo_timestamp_timeout` | `5` (base), `15` (developer), `0` (security) | Profile-aware credential cache duration |
| `user_sudo_use_pty` | `true` | CIS 5.3.5: allocate PTY for sudo sessions |
| `user_sudo_logfile` | `/var/log/sudo.log` | CIS 5.3.7: sudo audit log path |
| `user_sudo_log_input` | `false` | Record stdin of sudo sessions |
| `user_sudo_log_output` | `false` | Record stdout/stderr of sudo sessions |
| `user_sudo_passwd_timeout` | `1` | Minutes to enter password at prompt |
| `user_sudo_logrotate_enabled` | `true` | Deploy logrotate config for sudo.log |
| `user_sudo_logrotate_frequency` | `"weekly"` | Rotation frequency |
| `user_sudo_logrotate_rotate` | `13` | Number of rotations to keep (~90 days) |

## Supported platforms

Arch Linux, Debian/Ubuntu, RedHat/EL, Void Linux, Gentoo

## Tags

| Tag | Description |
|-----|-------------|
| `user` | All tasks |
| `sudo` | Sudo install + policy deploy |
| `install` | Package installation only |
| `security` | CIS security checks and absent-user removal |
| `report` | Execution report output (requires `common` role) |

## CIS controls

| Control | Description |
|---------|-------------|
| CIS 5.3.4 | `sudoers timestamp_timeout <= 5` (or profile-aware) |
| CIS 5.3.5 | `sudoers use_pty` |
| CIS 5.3.7 | `sudoers logfile` to `/var/log/sudo.log` |
| CIS 5.4.2 | Restrictive default umask via `/etc/profile.d/` |
| CIS 5.4.3 | Root account locked (no direct password login) |
| CIS 5.5.1 | `password_expire_max` for all managed users |
| CIS 5.5.2 | `password_expire_min` for all managed users |

## Molecule testing

Three scenarios covering different environments:

| Scenario | Driver | Platforms | Notes |
|----------|--------|-----------|-------|
| `default` | localhost | Arch Linux (current host) | Fast iteration, uses vault |
| `docker` | Docker | Arch Linux (systemd container) | CI/CD integration |
| `vagrant` | Vagrant + libvirt | Arch Linux, Ubuntu 24.04 | Full PAM, real shadow |

All scenarios share `molecule/shared/converge.yml` and `molecule/shared/verify.yml` with **29 assertions** (27 cross-platform + 2 OS-specific).

Run scenarios:

```bash
# Default (localhost, Arch only)
molecule test -s default

# Docker (requires Docker + arch-systemd image)
molecule test -s docker

# Vagrant (requires Vagrant + libvirt/KVM)
molecule test -s vagrant
```

## Example usage

```yaml
- hosts: workstations
  roles:
    - role: user
      vars:
        user_owner:
          name: alice
          shell: /bin/zsh
          groups: [wheel, docker, video, audio]
          password_hash: "{{ vault_alice_password }}"
          update_password: on_create
          umask: "027"
          password_max_age: 90
          password_min_age: 1
          password_warn_age: 14
        user_additional_users:
          - name: bob
            shell: /bin/bash
            groups: [video, audio]
            sudo: false
            password_hash: "{{ vault_bob_password }}"
            update_password: on_create
            umask: "077"
```
