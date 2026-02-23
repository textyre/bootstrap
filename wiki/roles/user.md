# user role

Manages user accounts on workstations: primary owner user, optional additional users,
sudo hardening, SSH authorized keys, password aging, and umask configuration.

## Variables

### Owner user

| Variable | Default | Description |
|----------|---------|-------------|
| `user_owner.name` | `SUDO_USER` or current user | Primary admin user |
| `user_owner.shell` | `/bin/bash` | Login shell |
| `user_owner.groups` | `[user_sudo_group]` | Supplementary groups |
| `user_owner.password_hash` | `""` (account locked) | Pre-hashed sha512 from vault |
| `user_owner.update_password` | `on_create` | `always` or `on_create` |
| `user_owner.ssh_keys` | `[]` | List of public key strings |
| `user_owner.umask` | `"027"` | CIS 5.4.2 login umask |
| `user_owner.password_max_age` | `365` | CIS 5.5.1 — days before must change |
| `user_owner.password_min_age` | `1` | CIS 5.5.2 — days before can change |
| `user_owner.password_warn_age` | `7` | Days before expiry to warn |

### Feature toggles

| Variable | Default | Description |
|----------|---------|-------------|
| `user_manage_ssh_keys` | `true` | Manage `~/.ssh/authorized_keys` |
| `user_manage_password_aging` | `true` | Apply `password_expire_max/min` |
| `user_manage_umask` | `true` | Deploy `/etc/profile.d/umask-<user>.sh` |
| `user_verify_root_lock` | `true` | Assert root has locked/empty password |

### Sudo policy

| Variable | Default | Description |
|----------|---------|-------------|
| `user_sudo_group` | `wheel` (non-Debian) / `sudo` (Debian) | Group with sudo access |
| `user_sudo_timestamp_timeout` | `5` (default), `15` (developer), `0` (security) | Minutes sudo caches credentials |
| `user_sudo_use_pty` | `true` | CIS 5.3.5 |
| `user_sudo_logfile` | `/var/log/sudo.log` | CIS 5.3.7 |
| `user_sudo_passwd_timeout` | `1` | CIS 5.3.6: minutes to enter password |

## Profile Behavior

| Profile | `user_sudo_timestamp_timeout` |
|---------|-------------------------------|
| (none) | 5 minutes |
| `developer` | 15 minutes (exceeds CIS 5.3.4 by design) |
| `security` | 0 minutes (always re-enter) |

Profile priority: `security` overrides `developer` when both are set.

## Vault Integration

Store the password hash in vault:

```yaml
# inventory/group_vars/all/vault.yml (ansible-vault encrypted)
vault_owner_password_hash: "$6$rounds=656000$..."
```

Reference in inventory:

```yaml
# inventory/host_vars/mymachine.yml
user_owner:
  name: textyre
  password_hash: "{{ vault_owner_password_hash }}"
```

Generate hash:
```bash
python3 -c "import crypt; print(crypt.crypt('mypassword', crypt.mksalt(crypt.METHOD_SHA512)))"
```

## SSH Key Setup

```yaml
user_owner:
  name: textyre
  ssh_keys:
    - "ssh-ed25519 AAAAC3... textyre@laptop"
    - "ssh-ed25519 AAAAC3... textyre@phone"
```

## Additional Users Example

```yaml
user_additional_users:
  - name: alice
    shell: /bin/bash
    groups: [video, audio]
    sudo: false
    password_hash: "{{ vault_alice_password }}"
    umask: "077"
    password_max_age: 90
  - name: bob
    shell: /bin/bash
    groups: [video, audio]
    sudo: true
    password_hash: "{{ vault_bob_password }}"
```

## CIS Controls

| CIS ID | Control | Default |
|--------|---------|---------|
| 5.3.4 | sudo timestamp_timeout <= 5 min | 5 (dev: 15, security: 0) |
| 5.3.5 | sudo use_pty | `true` |
| 5.3.6 | sudo passwd_timeout | 1 minute |
| 5.3.7 | sudo logfile | `/var/log/sudo.log` |
| 5.4.2 | umask 027 for users | 027 (owner), 077 (additional) |
| 5.4.3 | root account locked | assert only (no change) |
| 5.5.1 | password_expire_max | 365 days |
| 5.5.2 | password_expire_min | 1 day |

## Dependencies

None. The role is self-contained.
`ansible.posix` collection required (listed in `ansible/requirements.yml`).

## Tags

| Tag | What it runs |
|-----|-------------|
| `user` | Everything |
| `sudo` | sudo install + policy deployment |
| `ssh` | authorized_keys management |
| `security` | CIS security checks |
| `report` | Reporting tasks only |
| `cis_5.3.4` | sudo timeout task |
| `cis_5.4.2` | umask tasks |
| `cis_5.4.3` | root lock verification |
| `cis_5.5.1` | password_expire_max |
| `cis_5.5.2` | password_expire_min |
