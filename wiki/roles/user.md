# user role

Configures local workstation accounts, their sudo access, password aging,
login-shell umask, root password lock, and sudo-log rotation policy.

The complete variable reference, examples, troubleshooting, and test failure
guide live in [`ansible/roles/user/README.md`](../../ansible/roles/user/README.md).

## Contract

The role creates and maintains one owner account and optional additional local
accounts. It adds requested supplementary groups, grants sudo access, deploys a
validated sudoers policy, configures password aging and login umask, locks the
root password, and deploys the sudo-log rotation policy.

The role does not remove accounts or group memberships. It also does not own
package installation, arbitrary application groups, shell installation, SSH,
PAM/faillock, dotfiles, or desktop sessions. `sudo`, `visudo`, configured shell
executables, and non-sudo supplementary groups must already exist.

## Pipeline

`validate -> load vars -> owner -> additional users -> sudo -> security -> report`

| Phase | Result |
|-------|--------|
| Validate | Reject unsupported OS families before mutation |
| Load vars | Load the platform sudo group and sudo-log group |
| Owner | Configure the primary account, aging, and login umask |
| Additional users | Configure optional accounts and add requested groups |
| Sudo | Deploy validated sudoers and sudo-log rotation policies |
| Security | Lock the root password when enabled |
| Report | Render the informational execution report |

There is no verification phase inside the role. Molecule performs behavioral
verification after convergence and idempotence.

## Important Variable Behavior

| Setting | Actual behavior |
|---------|-----------------|
| Empty `password_hash` | The role does not change the password |
| `update_password: on_create` | A supplied hash is applied only while creating the account |
| `groups` | Listed groups are added; existing memberships are retained |
| `sudo: true` | Adds the platform sudo group |
| `sudo: false` | Does not add sudo access and does not revoke existing access |
| `user_manage_password_aging: false` | Preserves existing password-aging values |
| `user_manage_umask: false` | Skips deployment and does not remove an existing profile |
| `user_manage_root_lock: false` | Skips locking and does not unlock root |

Platform sudo groups are `sudo` on Debian/Ubuntu and `wheel` on Arch,
Fedora/RedHat, Void, and Gentoo. Automated scenarios currently cover Arch and
Ubuntu only.

## Runtime Environments

| Environment | Behavior |
|-------------|----------|
| Bare metal | Applies the complete account and sudo contract to the workstation |
| VM guest | Applies the same contract inside the guest OS without affecting host users |
| Docker | Exercises account state, sudo policy, aging, root lock, and login-shell umask; graphical login and PAM are outside the scenario |

## Testing

| Scenario | Sequence | Coverage |
|----------|----------|----------|
| Default | `syntax -> converge -> idempotence -> verify` | Prepared disposable Arch test host |
| Docker | `syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy` | Arch and Ubuntu containers |
| Vagrant/libvirt | `syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy` | Arch and Ubuntu VMs |

The shared behavioral verify checks:

1. The administrative test account is authorized by sudo policy.
2. The regular test account is denied by sudo policy.
3. Login shells apply owner umask `0027` and additional-account umask `0077`.

Tests deliberately do not repeat account, file, mode, shadow-field, or template
checks already owned by Ansible modules. All execution uses the approved remote
VM or CI workflow; it is not run locally.
