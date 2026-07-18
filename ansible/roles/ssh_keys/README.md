# ssh_keys

Manages SSH key files for one existing user.

The role owns only the user's SSH key state:

- ensures `~/.ssh` exists for `ssh_keys_user`;
- optionally writes inbound SSH public keys to `~/.ssh/authorized_keys`;
- generates the user's target-local SSH keypair.

It does not create users, remove users, configure `sshd`, install packages, restart SSH services, or manage firewall rules. The `user` role must create `ssh_keys_user` before this role runs.

## Execution Flow

1. **Validate prerequisites** (`tasks/validate.yml`) -- checks supported OS family.
2. **Detect account home** (`tasks/detect.yml`) -- reads the passwd database for the existing user home.
3. **Configure SSH key state** (`tasks/configure/main.yml`) -- creates `.ssh`, manages `authorized_keys` when keys are declared, and generates the user keypair when enabled.
4. **Report** (`tasks/main.yml`) -- renders the final Ansible execution report.

There is no separate assertion phase for this role. Successful converge and idempotence are the test signal.

## Variables

Concrete values should live in inventory. `defaults/main.yml` declares the external contract.

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_keys_user` | `{{ target_user }}` | Existing user whose SSH files are managed. |
| `ssh_keys_authorized_keys` | `[]` | Public keys allowed to log in as `ssh_keys_user`. Empty means `authorized_keys` is not managed. |
| `ssh_keys_exclusive` | `false` | When `true`, `authorized_keys` contains only keys from `ssh_keys_authorized_keys`. |
| `ssh_keys_generate_user_key` | `true` | Generate `ssh_keys_user` keypair on the target host. |
| `ssh_keys_user_key_type` | `ed25519` | Key type passed to `community.crypto.openssh_keypair`. Common values: `ed25519`, `rsa`, `ecdsa`. |

Internal variables live in `vars/main.yml`.

| Variable | Description |
|----------|-------------|
| `_ssh_keys_supported_os` | OS families accepted by `validate.yml`. |

## Inventory Example

```yaml
ssh_keys_user: "{{ target_user }}"
ssh_keys_authorized_keys:
  - "ssh-ed25519 AAAA... alice@laptop"
ssh_keys_exclusive: false
ssh_keys_generate_user_key: true
ssh_keys_user_key_type: ed25519
```

`ssh_keys_authorized_keys` are public keys. They allow holders of the matching private keys to log in as `ssh_keys_user`.

The generated keypair is different: it is created on the target host as `~/.ssh/id_<type>` and `~/.ssh/id_<type>.pub`. It is for outbound identity from that machine, for example adding the public key to GitHub or GitLab.

## Platform Behavior

The role behaves the same on all supported OS families: Archlinux, Debian, RedHat, Void, and Gentoo.

| Item | State |
|------|-------|
| `.ssh` directory | `~/.ssh`, owner=user, mode `0700` |
| `authorized_keys` | Managed by `ansible.posix.authorized_key` only when `ssh_keys_authorized_keys` is not empty |
| Generated private key | `~/.ssh/id_<ssh_keys_user_key_type>`, owner=user, mode `0600` |
| Generated public key | `~/.ssh/id_<ssh_keys_user_key_type>.pub`, owner=user |

## Dependencies

The role assumes:

- `ssh_keys_user` already exists;
- `ssh-keygen` exists on the target when `ssh_keys_generate_user_key: true`;
- project collections from `ansible/requirements.yml` are installed.

Collections:

- `ansible.posix` for `ansible.posix.authorized_key`;
- `community.crypto` for `community.crypto.openssh_keypair`.

Role dependency:

- `common` for execution reporting.

## Testing

The Molecule scenarios run syntax, prepare, converge, and idempotence. The shared converge play applies:

- `authorized_keys` deployment;
- exclusive replacement of old undeclared keys;
- generated private and public keypair.

They do not use a separate Ansible assertion playbook for module-level results.

Per project rules, run Ansible/Molecule through the remote VM or CI, not directly on the local machine.

## Troubleshooting

| Symptom | Meaning | Fix |
|---------|---------|-----|
| User lookup fails | `ssh_keys_user` does not exist on the target. | Run the `user` role first or set `ssh_keys_user` to an existing user. |
| `ssh-keygen` missing | Key generation is enabled but OpenSSH client tools are not installed. | Install the OS OpenSSH client package before enabling keygen. |
| Manually added keys disappeared | `ssh_keys_exclusive: true` makes `ssh_keys_authorized_keys` the complete source of truth. | Add required public keys to `ssh_keys_authorized_keys` or disable exclusive mode. |
| SSH login still fails | Key files are managed, but sshd policy is outside this role. | Check the `ssh` role and sshd settings such as `PubkeyAuthentication`. |

## File Map

| File | Purpose |
|------|---------|
| `defaults/main.yml` | External role contract. |
| `vars/main.yml` | Internal constants. |
| `tasks/main.yml` | Role orchestrator. |
| `tasks/validate.yml` | Supported platform check. |
| `tasks/detect.yml` | Passwd/home detection. |
| `tasks/configure/directories.yml` | `.ssh` directory state. |
| `tasks/configure/authorized_keys.yml` | `authorized_keys` deployment. |
| `tasks/configure/keygen.yml` | Target-local keypair generation. |
| `molecule/shared/prepare.yml` | Test account setup. |
| `molecule/shared/converge.yml` | Shared role converge. |
