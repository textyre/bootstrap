# ssh_keys

Manages SSH authorized_keys deployment and optional keypair generation for user accounts.

## Execution flow

1. **Assert supported OS** (`tasks/main.yml`) — validates `ansible_facts['os_family']` is in the supported list. Fails if OS is not Arch, Debian, RedHat, Void, or Gentoo.
2. **Compute user lists** (`tasks/main.yml`) — pre-filters `ssh_keys_users` into present, present-with-keys, and absent user lists. Used by all subsequent steps.
3. **Ensure .ssh directories** (`tasks/main.yml`) — creates `~/.ssh` with mode `0700` for all present users that have SSH keys defined. Shared by authorized_keys and keygen steps.
4. **Deploy authorized_keys** (`tasks/authorized_keys.yml`) — adds SSH public keys from `accounts[].ssh_keys` via `ansible.posix.authorized_key`. Removes `authorized_keys` for absent users. Skipped when `ssh_keys_manage_authorized_keys: false`.
5. **Generate keypairs** (`tasks/keygen.yml`) — generates SSH keypairs (ed25519 by default) on target machines via `community.crypto.openssh_keypair`. Skipped when `ssh_keys_generate_user_keys: false` (default).
6. **Verify** (`tasks/verify.yml`) — checks `.ssh` directory permissions (0700), `authorized_keys` existence, and generated keypair existence (when keygen enabled). Fails if any check does not pass.
7. **Report** (`tasks/main.yml`) — writes execution report via `common/report_phase.yml` and `common/report_render.yml`. Separate phases for authorized_keys and keygen.

### Handlers

This role does not define handlers. SSH service restart is handled by the `ssh` role.

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `ssh_keys_manage_authorized_keys` | `true` | safe | Deploy `authorized_keys` from the `accounts` data source |
| `ssh_keys_generate_user_keys` | `false` | safe | Generate SSH keypairs on target machines |
| `ssh_keys_key_type` | `ed25519` | safe | Key type for generation: `ed25519`, `rsa`, or `ecdsa` |
| `ssh_keys_exclusive` | `false` | careful | Remove keys not listed in `accounts[].ssh_keys` from `authorized_keys`. When `true`, any manually added keys will be deleted |
| `ssh_keys_supported_os` | 5 OS families | internal | List of supported `os_family` values. Do not change unless adding platform support |

### Internal variables

| Variable | Set by | Description |
|----------|--------|-------------|
| `_ssh_keys_present_users` | `set_fact` in main.yml | Users with `state: present`, pre-filtered |
| `_ssh_keys_present_users_with_keys` | `set_fact` in main.yml | Present users that have `ssh_keys` defined |
| `_ssh_keys_absent_users` | `set_fact` in main.yml | Users with `state: absent`, pre-filtered |

### Data source

The role reads user and key data from the shared `accounts` variable (same source used by the `user` role). When `accounts` is not defined, falls back to `user_owner` + `user_additional_users` for backward compatibility.

## Examples

### Deploying SSH keys for users

```yaml
# In group_vars/all/accounts.yml:
accounts:
  - name: alice
    state: present
    ssh_keys:
      - "ssh-ed25519 AAAA... alice@laptop"
      - "ssh-ed25519 AAAA... alice@phone"
  - name: bob
    state: absent   # authorized_keys will be removed
```

### Generating keypairs on target machines

```yaml
# In group_vars/all/ssh.yml:
ssh_keys_generate_user_keys: true
ssh_keys_key_type: ed25519
```

This creates `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub` for each present user.

### Using exclusive mode (remove unlisted keys)

```yaml
# In group_vars/all/ssh.yml:
ssh_keys_exclusive: true
```

Any keys in `authorized_keys` that are not in `accounts[].ssh_keys` will be removed. Use with caution — this can lock out users who added keys manually.

### Disabling authorized_keys management

```yaml
# In host_vars/<hostname>/ssh.yml:
ssh_keys_manage_authorized_keys: false
```

## Cross-platform details

| Aspect | All platforms |
|--------|--------------|
| `.ssh` directory path | `~/.ssh` (home dir from `getent passwd`) |
| `.ssh` directory mode | `0700` |
| `authorized_keys` path | `~/.ssh/authorized_keys` |
| `authorized_keys` mode | `0600` (set by `ansible.posix.authorized_key`) |
| Generated key path | `~/.ssh/id_<key_type>` |

This role does not install packages or manage services, so there are no OS-specific package names, service names, or config paths. The role works identically across all five supported OS families.

## Logs

### Role output

This role does not write log files to the filesystem. All output is via Ansible execution report (`common/report_phase.yml`).

| Output | Where | Contents |
|--------|-------|----------|
| Execution report | Ansible stdout | Phase summary: users count, keygen status, exclusive mode status |
| `authorized_key` changes | Ansible stdout | Added/removed keys per user (suppressed by `no_log: true` for security) |

### Audit trail

SSH key changes are visible via:
- `stat` on `~/.ssh/authorized_keys` — modification timestamp shows when keys last changed
- `git log` on inventory files — tracks who changed `accounts[].ssh_keys` and when

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in supported list | Check `ansible_facts['os_family']` matches one of: Archlinux, Debian, RedHat, Void, Gentoo |
| "user not found" error in keygen | User does not exist on target | Ensure `user` role runs before `ssh_keys` in the playbook |
| Keys deployed but SSH login fails | Check `sshd_config` allows pubkey auth | Verify `PubkeyAuthentication yes` in `/etc/ssh/sshd_config` and `AuthorizedKeysFile` path matches |
| Exclusive mode removed manually-added keys | `ssh_keys_exclusive: true` removes all keys not in `accounts[].ssh_keys` | Add all required keys to the `accounts` data source before enabling exclusive mode |
| authorized_keys not removed for absent user | User home directory does not exist | The role removes the file if the home dir exists. If home was already deleted, the file is gone too |
| Idempotence failure on keygen | `community.crypto.openssh_keypair` regenerates keys when comment changes | Ensure `ansible_hostname` is stable between runs |
| "collection not found: ansible.posix" | Collection dependencies not installed | Run `ansible-galaxy collection install -r ansible/requirements.yml` |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Local (fast) | `molecule test` | After changing task logic or variables | Syntax, idempotence, basic verification on localhost |
| Docker (CI) | `molecule test -s docker` | After changing any role files | Arch + Ubuntu containers, full verification |
| Vagrant (full) | `molecule test -s vagrant` | After changing OS-specific logic | Real VMs with Arch + Ubuntu, full system validation |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | What is checked | Requirement |
|----------|----------------|-------------|
| Permissions | `.ssh` directory exists, mode 0700, correct owner | TEST-008 |
| Config files | `authorized_keys` exists, mode 0600, correct owner, correct key content | TEST-008 |
| Exclusive mode | Second key removed after exclusive=true converge | TEST-008 |
| Absent user cleanup | `authorized_keys` removed for `state: absent` user | TEST-008 |
| Keygen | `id_ed25519` private key exists, mode 0600; public key exists | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `user testuser does not exist` | prepare.yml did not run | Run full sequence: `molecule test`, not just `molecule converge` |
| `No module named 'community.crypto'` | Collection not installed | `ansible-galaxy collection install -r ansible/requirements.yml` |
| Idempotence failure on authorized_keys | `exclusive: true` with changing key list | Ensure converge vars are stable between plays |
| `authorized_keys for absent_user should have been removed` | prepare.yml did not plant the test file | Run `molecule destroy && molecule test` to reset |
| Vagrant: `Python not found` | Arch VM needs bootstrap | Check `prepare.yml` imports `prepare-vagrant.yml` |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `ssh_keys` | Entire role | Full apply: `ansible-playbook playbook.yml --tags ssh_keys` |
| `ssh_keys,security` | Authorized keys deployment only | Re-deploy keys without keygen: `ansible-playbook playbook.yml --tags ssh_keys,security` |
| `ssh_keys,report` | Execution report only | Re-generate report: `ansible-playbook playbook.yml --tags ssh_keys,report` |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No -- override via inventory |
| `tasks/main.yml` | Execution flow orchestrator, user list computation | When adding/removing steps |
| `tasks/authorized_keys.yml` | authorized_keys deployment and cleanup | When changing key deployment logic |
| `tasks/keygen.yml` | SSH keypair generation | When changing keygen logic |
| `tasks/verify.yml` | Post-deploy self-checks | When changing verification logic |
| `handlers/main.yml` | Empty -- sshd restart handled by ssh role | Rarely |
| `meta/main.yml` | Galaxy metadata and collection dependency docs | When changing role metadata |
| `molecule/shared/` | Shared converge and verify playbooks | When changing test coverage |
| `molecule/default/` | Local test scenario | When changing local test config |
| `molecule/docker/` | Docker CI scenario (Arch + Ubuntu) | When changing container test config |
| `molecule/vagrant/` | Vagrant scenario (Arch + Ubuntu VMs) | When changing VM test config |
