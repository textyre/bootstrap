# user

Manages local workstation accounts, their sudo access, and account security policy.

## Execution Flow

1. **Validate** (`tasks/validate/main.yml`) -- stops before mutation unless the OS family is Archlinux, Debian, RedHat, Void, or Gentoo.
2. **Load vars** (`tasks/load/main.yml`) -- loads the platform sudo group and sudo-log group from `vars/<os-family>.yml`.
3. **Owner** (`tasks/owner.yml`) -- creates or updates the primary account and home directory, adds supplementary groups, optionally applies a supplied password hash on account creation, configures password aging, and deploys `/etc/profile.d/umask-<name>.sh`.
4. **Additional users** (`tasks/additional_users.yml`) -- creates optional accounts and home directories, adds their supplementary and sudo groups, configures requested password aging, and deploys per-user umask profiles.
5. **Sudo** (`tasks/sudo.yml`) -- deploys `/etc/sudoers.d/<wheel-or-sudo>` with `visudo` validation and optionally deploys `/etc/logrotate.d/sudo`.
6. **Security** (`tasks/security.yml`) -- locks the root account password when `user_manage_root_lock` is enabled. It does not change SSH key access or `sshd_config`.
7. **Report** (`tasks/report/main.yml`) -- renders the accumulated phase report. It does not calculate or change account state.

The role has no handlers and no in-role verification phase. Molecule performs
behavioral verification after convergence and idempotence.

## Variables

### Configurable (`defaults/main.yml`)

Override these through inventory. Do not edit `defaults/main.yml` for a single host.

#### Primary Owner

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_owner.name` | `user_name`, else `$SUDO_USER`, else current Ansible user | careful | Account managed as the workstation owner. A wrong value creates or changes the wrong account |
| `user_owner.shell` | `user_shell`, else `/bin/bash` | careful | Login shell path. The executable must already exist |
| `user_owner.groups` | `user_groups`, else platform sudo group | careful | Supplementary groups to add. Existing memberships are retained because the role uses `append: true` |
| `user_owner.password_hash` | `""` | careful | Precomputed Linux password hash. Empty means the role does not change the password; plaintext is not valid here |
| `user_owner.update_password` | `on_create` | careful | With `on_create`, a supplied hash is used only when creating the account. `always` replaces the existing hash |
| `user_owner.umask` | `"027"` | safe | Login-shell umask: owner has full access, group has read/execute, others have no access |
| `user_owner.password_max_age` | `365` | careful | Maximum days before the password expires |
| `user_owner.password_min_age` | `1` | careful | Minimum days before the password may be changed again |
| `user_owner.password_warn_age` | `7` | safe | Days before password expiry when login starts warning the user |

#### Additional Accounts

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_additional_users` | `[]` | careful | Additional local account definitions. Empty means no additional accounts are managed |

Each entry supports these fields:

| Field | Default | Safety | Effect |
|-------|---------|--------|--------|
| `name` | required | careful | Local account name |
| `shell` | `/bin/bash` | careful | Login shell; the executable must already exist |
| `groups` | `[]` | careful | Supplementary groups to add; listed groups must already exist and previous memberships are retained |
| `sudo` | `false` | careful | `true` adds the platform sudo group. `false` does not remove existing sudo access |
| `password_hash` | `""` | careful | Precomputed Linux password hash. Empty leaves the password unmanaged |
| `update_password` | `on_create` | careful | Controls when a supplied password hash is applied |
| `umask` | `"077"` | safe | Login-shell umask: only the account owner receives permissions by default |
| `password_max_age` | unmanaged | careful | Maximum password age; omission preserves the existing value |
| `password_min_age` | unmanaged | careful | Minimum password age; omission preserves the existing value |
| `password_warn_age` | `7` | safe | Days before password-expiry warning |

#### Account Policy

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_manage_password_aging` | `true` | careful | Applies configured max/min/warn ages. `false` preserves existing aging values |
| `user_manage_umask` | `true` | safe | Deploys login-shell umask profiles. `false` skips management and does not remove existing profiles |
| `user_manage_root_lock` | `true` | careful | Locks the root password. `false` does not unlock root |

#### Sudo Policy

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_sudo_timestamp_timeout` | `5`; developer `15`; security `0` | careful | Minutes sudo credentials remain cached. The value is derived from `workstation_profiles` |
| `user_sudo_use_pty` | `true` | careful | Adds `Defaults use_pty` to sudoers |
| `user_sudo_logfile` | `/var/log/sudo.log` | safe | Dedicated sudo event log. Empty disables the logfile directive and logrotate deployment |
| `user_sudo_log_input` | `false` | careful | Enables sudo input recording, which can capture sensitive data |
| `user_sudo_log_output` | `false` | careful | Enables sudo output recording, which can consume significant disk space |
| `user_sudo_passwd_timeout` | `1` | safe | Minutes allowed for entering a sudo password |
| `user_sudo_config_overwrite` | `{}` | internal | Additional sudoers `Defaults` directives. Invalid keys or values make `visudo` reject the generated policy |
| `user_sudo_logrotate_enabled` | `true` | safe | Deploys `/etc/logrotate.d/sudo` when `user_sudo_logfile` is non-empty |
| `user_sudo_logrotate_frequency` | `weekly` | safe | Rotation interval written to the sudo logrotate policy |
| `user_sudo_logrotate_rotate` | `13` | safe | Number of compressed rotated sudo logs retained |

### Internal Mappings (`vars/`)

These are role implementation details and must not be overridden in inventory.

| File | What it contains | When to edit |
|------|------------------|--------------|
| `vars/main.yml` | Supported Ansible OS families | When deliberately adding or removing platform support |
| `vars/archlinux.yml` | `wheel` sudo group and `root` sudo-log group | When Arch platform conventions change |
| `vars/debian.yml` | `sudo` sudo group and `adm` sudo-log group | When Debian/Ubuntu platform conventions change |
| `vars/redhat.yml` | `wheel` sudo group and `root` sudo-log group | When Fedora/RedHat platform conventions change |
| `vars/void.yml` | `wheel` sudo group and `root` sudo-log group | When Void platform conventions change |
| `vars/gentoo.yml` | `wheel` sudo group and `root` sudo-log group | When Gentoo platform conventions change |

## Examples

### Configure the workstation owner

In `ansible/inventory/group_vars/all/system.yml` or a host-specific inventory file:

```yaml
user_owner:
  name: alice
  shell: /usr/bin/zsh
  groups:
    - wheel
    - video
    - audio
  password_hash: "{{ vault_alice_password_hash }}"
  update_password: on_create
  umask: "027"
  password_max_age: 365
  password_min_age: 1
  password_warn_age: 7
```

`password_hash` must contain the complete precomputed Linux hash stored in
`/etc/shadow` format, not the plaintext password. With `on_create`, it is not
replaced on later runs.

### Configure additional accounts

In `ansible/inventory/group_vars/all/system.yml` or a host-specific inventory file:

```yaml
user_additional_users:
  - name: bob
    shell: /bin/bash
    groups:
      - video
      - audio
    sudo: false
    password_hash: ""
    update_password: on_create
    umask: "077"
    password_max_age: 90
    password_min_age: 0
    password_warn_age: 7

  - name: carol
    shell: /bin/bash
    groups: []
    sudo: true
    password_hash: "{{ vault_carol_password_hash }}"
    update_password: on_create
    umask: "077"
```

Bob is not added to the sudo group. Carol is added to the platform sudo group.
Neither declaration removes groups already assigned to the account.

## Role Contract And Environments

The role owns local account creation and maintenance, sudo policy, password
aging, login-shell umask, root password locking, and the sudo-log rotation
policy. It does not own SSH policy, PAM/faillock, dotfiles, shell installation,
application groups, package installation, desktop sessions, or account removal.

Prerequisites:

- Ansible facts have been gathered and the play can use root privileges.
- `sudo` and `visudo` are already installed.
- `logrotate` is installed elsewhere when `/etc/logrotate.d/sudo` must run.
- Configured shell executables and non-sudo supplementary groups already exist.

| Environment | Behavior |
|-------------|----------|
| Bare metal | Applies the complete role contract to the physical workstation |
| VM guest | Applies the same contract inside the guest; host and hypervisor users are unaffected |
| Docker | Accounts, sudo policy, password aging, root lock, and login-shell profiles converge normally; graphical login and PAM are outside the test |

## Policy Rationale

| Policy | Default | User-visible result |
|--------|---------|---------------------|
| Owner password | unmanaged | Existing credentials are preserved unless an operator supplies a hash |
| Password aging | max 365, min 1, warn 7 | Passwords eventually expire, rapid repeated changes are restricted, and users receive advance warning |
| Owner umask | `027` | New files are private from other users while group access remains possible |
| Additional account umask | `077` | New files are private to that account by default |
| Sudo timeout | base 5, developer 15, security 0 | Controls how often the operator must re-enter the sudo password |
| Sudo PTY | enabled | Sudo commands run in a separate pseudo-terminal |
| Sudo event log | `/var/log/sudo.log` | Sudo records command events in a dedicated file |
| Log rotation | weekly, 13 copies | Sudo logs are compressed and retained for roughly one quarter |
| Root password | locked | Direct root password authentication is disabled; sudo and SSH keys are separate mechanisms |

The CIS identifiers used by the tasks follow the project mappings in
[`wiki/standards/security-standards.md`](../../../wiki/standards/security-standards.md).

## Cross-Platform Details

The role supports five Ansible OS families. Automated Docker and Vagrant tests
currently cover Arch Linux and Ubuntu only.

| Aspect | Arch Linux | Ubuntu/Debian | Fedora/RedHat | Void | Gentoo |
|--------|------------|---------------|---------------|------|--------|
| Sudo group | `wheel` | `sudo` | `wheel` | `wheel` | `wheel` |
| Sudo-log group | `root` | `adm` | `root` | `root` | `root` |
| Managed sudoers file | `/etc/sudoers.d/wheel` | `/etc/sudoers.d/sudo` | `/etc/sudoers.d/wheel` | `/etc/sudoers.d/wheel` | `/etc/sudoers.d/wheel` |
| Managed logrotate file | `/etc/logrotate.d/sudo` | `/etc/logrotate.d/sudo` | `/etc/logrotate.d/sudo` | `/etc/logrotate.d/sudo` | `/etc/logrotate.d/sudo` |
| Package ownership | External | External | External | External | External |
| Automated scenario | Arch Docker and VM | Ubuntu Docker and VM | Not currently covered | Not currently covered | Not currently covered |

## Logs

| File | Contents | Rotation |
|------|----------|----------|
| `/var/log/sudo.log` | Sudo authentication and command events | `weekly`, `13` copies, compressed and delayed compression by `/etc/logrotate.d/sudo` |
| Sudo I/O logs | Command input/output when `user_sudo_log_input` or `user_sudo_log_output` is enabled | Location and retention follow the installed sudo configuration; this role does not configure an I/O log directory or rotation |

The event log is created by sudo when sudo is used, not by the Ansible template.
If `user_sudo_logfile` is empty, the role configures no dedicated event log and
does not deploy its logrotate policy.

Common inspection commands:

```bash
tail -n 50 /var/log/sudo.log
grep -E 'COMMAND=|authentication failure|NOT in sudoers' /var/log/sudo.log
logrotate --debug /etc/logrotate.d/sudo
```

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role stops at supported-OS validation | Read the reported `ansible_facts.os_family` | Use one of the five supported OS families; do not bypass validation |
| `visudo` is not found | `command -v visudo` | Install the platform sudo package through the package-owning role, then rerun from a clean test environment |
| Account creation reports a missing group | `getent group <group>` | Correct the inventory or create the application group in its owning role before `user` runs |
| Account creation reports an invalid shell | `test -x <shell-path>` | Install the shell through the shell/package role or correct `user_owner.shell` |
| Expected sudo access is denied | `id <user>` and `sudo -U <user> -l` | Set `sudo: true` for an additional account or include the platform sudo group for the owner, then rerun the role |
| `sudo: false` did not revoke old access | `id <user>` | Expected: the role only adds memberships. Remove access through the explicitly owning account-removal workflow, not this role |
| Umask is unchanged in the current shell | `su - <user> -c umask` | Start a new login shell; `/etc/profile.d` does not retroactively change an existing session |
| Root still accepts an SSH key | `ssh -v root@<host>` | Expected: password locking does not disable SSH keys. Configure root SSH access in the SSH role |
| Sudo log is not rotated | `command -v logrotate` and `logrotate --debug /etc/logrotate.d/sudo` | Ensure logrotate is installed and scheduled by its owning system component |

## Testing

All Ansible and Molecule execution must use the project's remote VM or CI path.
Do not run these scenarios directly on the local workstation.

| Scenario | Sequence | Execution path | What it tests |
|----------|----------|----------------|---------------|
| Default | `syntax -> converge -> idempotence -> verify` | `task test-user` on a disposable remote clone | Prepared Arch host convergence, zero-change rerun, and behavioral verify |
| Docker | `syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy` | Changed-role Docker CI workflow | Arch/Ubuntu container convergence, zero-change rerun, and behavior |
| Vagrant/libvirt | `syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy` | Changed-role Vagrant CI workflow | Arch/Ubuntu VM convergence, zero-change rerun, and behavior |

All scenarios use `molecule/shared/converge.yml`. It configures:

- `testuser_owner` as the primary owner with umask `027`;
- `testuser_extra` as a regular account in `video` with umask `077`;
- `testuser_with_sudo` as an administrative account with umask `077`.

Docker and Vagrant use `molecule/shared/prepare.yml` to install the external
`logrotate` prerequisite and create the test-only `video` group. Arch Vagrant
preparation also keeps passwordless sudo for the `vagrant` automation account
so the role's password-requiring `wheel` policy does not interrupt later role
tasks or the idempotence run.

### Behavioral Verification

`molecule/shared/verify.yml` checks only behavior not guaranteed by an
individual Ansible module:

1. The sudo policy authorizes `testuser_with_sudo` to run `/usr/bin/true`.
2. The sudo policy denies `testuser_extra` permission to run `/usr/bin/true`.
3. Login shells report umask `0027` for the owner and `0077` for both additional accounts.

It intentionally does not re-check account existence, group records, shadow
fields, deployed files, modes, or template contents. `ansible.builtin.user` and
`ansible.builtin.template` already own those state guarantees, and the sudoers
template performs atomic `visudo` validation during convergence.

### Success Criteria

- Syntax, converge, idempotence, and verify complete without failed tasks.
- Idempotence reports `changed=0` on every tested host.
- Both sudo authorization checks return the expected decision.
- All three login-shell umask assertions pass.
- Docker and Vagrant destroy their temporary environments after the test.

### Common Test Failures

| Error | Cause | Fix |
|-------|-------|-----|
| `visudo: command not found` | Base test image does not provide the role prerequisite | Fix the base image or shared environment preparation; do not add package installation to this role |
| `group video does not exist` | Scenario preparation did not run | Run the full CI/Molecule sequence instead of converge alone |
| Administrative sudo assertion fails | The test account was not authorized by the generated platform policy | Inspect the converge result and platform sudo-group mapping; fix locally and restart from a fresh clone |
| Regular-user sudo assertion fails | A dirty test host already granted that account administrative access | Reset to a fresh disposable environment; the role deliberately does not remove memberships |
| Login umask assertion differs | The login shell did not source the managed `/etc/profile.d` script or the rendered value is wrong | Inspect the failed login-shell output and template logic; fix locally and restart the scenario |
| Vagrant loses become access after sudo configuration | The Arch test-only automation rule was not prepared or sorts before the managed `wheel` policy | Restore the scenario preparation rule and rerun on a fresh Vagrant instance |
| Idempotence reports changes | A role task does not converge to stable state | Fix the task locally; do not hide the change with `changed_when: false` |

## Tags

All role tasks inherit the `user` tag. Inner tags classify security controls but
are not independent entry points because validation and platform-variable loading
must run first.

| Tag | Scope | Use case |
|-----|-------|----------|
| `user` | Complete role | Supported tag for applying the complete account and sudo contract |
| `sudo` | Sudoers and sudo-log policy tasks | Classification of sudo policy output |
| `security` | Sudo hardening and root password lock | Classification of security-sensitive output |
| `cis_5.3.4` | Sudo timestamp policy | Trace the project CIS timeout mapping |
| `cis_5.3.5` | Sudo PTY policy | Trace the project CIS PTY mapping |
| `cis_5.3.7` | Dedicated sudo event log | Trace the project CIS logging mapping |
| `cis_5.4.1` | Password-expiry settings | Trace password aging output |
| `cis_5.4.2` | Per-user login umask | Trace umask profile output |
| `cis_5.4.3` | Root password lock | Trace root-lock output |
| `cis_5.5.1` | Maximum password age | Trace maximum-age output |
| `cis_5.5.2` | Minimum password age | Trace minimum-age output |

The supported complete-role invocation is `--tags user`. Running an inner tag
alone is not a supported partial workflow.

## File Map

| File | Purpose | When to edit |
|------|---------|--------------|
| `defaults/main.yml` | Public role variables | Change defaults only when changing the role contract; host choices belong in inventory |
| `vars/main.yml` | Supported OS-family list | When platform support changes |
| `vars/<os-family>.yml` | Platform sudo and log-group mappings | When a platform convention changes |
| `tasks/main.yml` | Pipeline orchestrator | When an agreed role phase is added or removed |
| `tasks/validate/main.yml` | Supported-platform validation | When the input/platform contract changes |
| `tasks/load/main.yml` | Platform mapping loader | When variable-loading architecture changes |
| `tasks/owner.yml` | Primary account, aging, and umask | When owner behavior changes |
| `tasks/additional_users.yml` | Additional accounts, sudo membership, aging, and umask | When additional-account behavior changes |
| `tasks/sudo.yml` | Sudoers and sudo-log rotation policy | When sudo policy changes |
| `tasks/security.yml` | Root password lock | When account-security behavior changes |
| `tasks/report/main.yml` | Final informational report | When report presentation changes |
| `templates/sudoers_hardening.j2` | Managed sudoers drop-in | When sudo directives change |
| `templates/sudo_logrotate.j2` | Managed sudo event-log rotation | When retention policy changes |
| `templates/user_umask.sh.j2` | Per-user login-shell umask | When shell application logic changes |
| `meta/main.yml` | Galaxy metadata and supported platforms | When role metadata changes |
| `molecule/shared/prepare.yml` | Shared external prerequisites for isolated scenarios | When the test environment contract changes |
| `molecule/shared/converge.yml` | Shared representative test configuration | When the tested contract changes |
| `molecule/shared/verify.yml` | Shared behavioral checks | When observable role behavior changes |
| `molecule/default/molecule.yml` | Prepared remote-host scenario | When the default execution path changes |
| `molecule/docker/` | Arch/Ubuntu container scenario and preparation | When container coverage changes |
| `molecule/vagrant/` | Arch/Ubuntu VM scenario and preparation | When VM coverage changes |
