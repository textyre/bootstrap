# user

Manages user accounts, sudo policy, and password hardening on workstations.

## Execution flow

1. **Preflight assert** (`tasks/main.yml`) -- fails if OS family is not in `user_supported_os`
2. **Load OS variables** (`vars/<os_family>.yml`) -- loads package names for the detected OS family
3. **Install sudo** (`tasks/install.yml`) -- installs the `sudo` package via `ansible.builtin.package`
4. **Remove absent users** (`tasks/main.yml`) -- removes users from the `accounts` list that have `state: absent`. Skips gracefully if list is empty.
5. **Configure owner** (`tasks/owner.yml`) -- creates the primary admin user with shell, groups, password hash, password aging (CIS 5.5.1/5.5.2 via `password_expire_max/min`), warn age (via `chage -W`), and deploys umask profile to `/etc/profile.d/umask-<name>.sh`
6. **Configure additional users** (`tasks/additional_users.yml`) -- creates extra users, optionally adds them to the sudo group (`sudo: true`), sets password aging and umask. Skips if `user_additional_users` is empty.
7. **Deploy sudo policy** (`tasks/sudo.yml`) -- deploys `/etc/sudoers.d/<group>` from template with CIS 5.3.4/5.3.5/5.3.7 controls. Validates syntax with `visudo -cf`. Deploys `/etc/logrotate.d/sudo` for audit log rotation.
8. **Security checks** (`tasks/security.yml`) -- asserts root account is locked (CIS 5.4.3). Skips if `user_verify_root_lock: false`.
9. **Verify** (`tasks/verify.yml`) -- read-only checks: owner exists, sudoers syntax valid, sudoers content correct, umask deployed, password aging matches, root lock, logrotate config exists, absent users removed
10. **Report** -- writes execution report via `common/report_phase` + `report_render`

## Variables

### Configurable (`defaults/main.yml`)

Override via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

#### Owner

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_owner.name` | `$SUDO_USER` or current user | careful | Primary admin username. Changing renames the managed account |
| `user_owner.shell` | `/bin/bash` | safe | Login shell |
| `user_owner.groups` | `[user_sudo_group]` | careful | Supplementary groups. Removing the sudo group locks out sudo access |
| `user_owner.password_hash` | `""` (account locked) | careful | Pre-hashed SHA-512 password. Empty = account locked (`!` in shadow) |
| `user_owner.update_password` | `on_create` | careful | `always` re-hashes every run; `on_create` sets once |
| `user_owner.umask` | `"027"` | safe | CIS 5.4.2 restrictive umask deployed to `/etc/profile.d/` |
| `user_owner.password_max_age` | `365` | careful | CIS 5.5.1: days before password must change. Setting too low locks out users |
| `user_owner.password_min_age` | `1` | safe | CIS 5.5.2: days before password can change |
| `user_owner.password_warn_age` | `7` | safe | Days before expiry to warn (applied via `chage -W`) |

#### Additional users

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_additional_users` | `[]` | safe | List of user dicts (same fields as `user_owner`, plus `sudo: bool`) |

#### Feature toggles

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_manage_password_aging` | `true` | careful | Set `password_expire_max/min` via `chage`. Disabling removes CIS 5.5.1/5.5.2 compliance |
| `user_manage_umask` | `true` | safe | Deploy `/etc/profile.d/umask-<user>.sh` per managed user |
| `user_verify_root_lock` | `true` | safe | CIS 5.4.3: assert root has no direct password login. Disable on systems where root must have a password |

#### Sudo policy

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `user_sudo_group` | `wheel` (Arch/RH/Void/Gentoo), `sudo` (Debian) | internal | Sudo group name. Auto-detected from OS family. Changing breaks sudoers file naming |
| `user_sudo_timestamp_timeout` | `5` (base), `15` (developer), `0` (security) | careful | Profile-aware credential cache duration in minutes. CIS 5.3.4 requires <= 5 |
| `user_sudo_use_pty` | `true` | internal | CIS 5.3.5: allocate PTY for sudo sessions. Disabling weakens security |
| `user_sudo_logfile` | `/var/log/sudo.log` | safe | CIS 5.3.7: sudo audit log path |
| `user_sudo_log_input` | `false` | careful | Record stdin of sudo sessions. Enables forensic logging but may capture passwords |
| `user_sudo_log_output` | `false` | careful | Record stdout/stderr of sudo sessions. Significant disk usage on busy systems |
| `user_sudo_passwd_timeout` | `1` | safe | Minutes to enter password at sudo prompt |
| `user_sudo_config_overwrite` | `{}` | careful | Dict of additional `Defaults` directives merged into the sudoers template. Each key is a directive name, value is the directive value. Overrides or extends the built-in sudo policy without modifying the template. See [Overriding sudo defaults](#overriding-sudo-defaults) |
| `user_sudo_logrotate_enabled` | `true` | safe | Deploy logrotate config for sudo.log |
| `user_sudo_logrotate_frequency` | `"weekly"` | safe | Rotation frequency |
| `user_sudo_logrotate_rotate` | `13` | safe | Number of rotations to keep (~90 days, CIS minimum retention) |

### Internal mappings (`vars/`)

These files contain OS-specific package mappings. Do not override via inventory -- edit the files directly only when adding package name support for a new distro.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/archlinux.yml` | `user_packages: [sudo]` | Never (unless Arch renames the package) |
| `vars/debian.yml` | `user_packages: [sudo]` | Never |
| `vars/redhat.yml` | `user_packages: [sudo]` | Never |
| `vars/void.yml` | `user_packages: [sudo]` | Never |
| `vars/gentoo.yml` | `user_packages: [app-admin/sudo]` | Never (Gentoo uses category/package format) |

## Examples

### Configuring the primary owner

```yaml
# In host_vars/mymachine.yml:
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
```

### Adding additional users

```yaml
# In group_vars/workstations/users.yml:
user_additional_users:
  - name: bob
    shell: /bin/bash
    groups: [video, audio]
    sudo: false
    password_hash: "{{ vault_bob_password }}"
    update_password: on_create
    umask: "077"
    password_max_age: 90
  - name: carol
    shell: /bin/bash
    groups: []
    sudo: true
    password_hash: "{{ vault_carol_password }}"
```

### Generating a password hash for vault

```bash
python3 -c "import crypt; print(crypt.crypt('mypassword', crypt.mksalt(crypt.METHOD_SHA512)))"
```

### Removing a user (zero-trust cleanup)

```yaml
# In host_vars/mymachine.yml:
accounts:
  - name: former_employee
    state: absent
```

### Overriding sudo defaults

```yaml
# In group_vars/all/sudo.yml:
user_sudo_config_overwrite:
  env_reset: "true"
  secure_path: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  mail_badpass: "true"
```

Each key-value pair renders as `Defaults key=value` in the sudoers file, appended after all built-in directives. Use this to add directives not covered by the dedicated variables (`user_sudo_use_pty`, `user_sudo_logfile`, etc.) without editing the template.

### Adjusting sudo timeout for a security-focused workstation

```yaml
# In group_vars/all/system.yml:
workstation_profiles:
  - security
# Result: user_sudo_timestamp_timeout = 0 (re-enter password every time)
```

## CIS controls

| CIS ID | Control | Implementation |
|--------|---------|---------------|
| 5.3.4 | `sudoers timestamp_timeout <= 5` | Profile-aware: 5 (base), 15 (developer), 0 (security) |
| 5.3.5 | `sudoers use_pty` | `user_sudo_use_pty: true` |
| 5.3.7 | `sudoers logfile` | `/var/log/sudo.log` with logrotate |
| 5.4.2 | Restrictive default umask | `/etc/profile.d/umask-<user>.sh` per managed user |
| 5.4.3 | Root account locked | Assertion only (does not lock root -- verifies it is already locked) |
| 5.5.1 | `password_expire_max` | Set via `ansible.builtin.user` `password_expire_max` parameter |
| 5.5.2 | `password_expire_min` | Set via `ansible.builtin.user` `password_expire_min` parameter |

## Cross-platform details

| Aspect | Arch Linux | Debian / Ubuntu | RedHat / Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|-----------------|------------|--------|
| Sudo package | `sudo` | `sudo` | `sudo` | `sudo` | `app-admin/sudo` |
| Sudo group | `wheel` | `sudo` | `wheel` | `wheel` | `wheel` |
| Sudoers path | `/etc/sudoers.d/wheel` | `/etc/sudoers.d/sudo` | `/etc/sudoers.d/wheel` | `/etc/sudoers.d/wheel` | `/etc/sudoers.d/wheel` |

## Logs

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| sudo.log | `/var/log/sudo.log` | All sudo invocations: user, command, timestamp | logrotate: weekly, 13 rotations (~90 days) |
| sudo I/O | `/var/log/sudo-io/` | stdin/stdout/stderr of sudo sessions (only if `user_sudo_log_input/output: true`) | Not rotated -- disable in production or monitor disk usage |

### Reading the logs

- Recent sudo usage: `tail -50 /var/log/sudo.log`
- Failed sudo attempts: `grep "NOT in sudoers" /var/log/sudo.log`
- Logrotate status: `cat /var/lib/logrotate/status | grep sudo`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| User cannot sudo | `groups <username>` -- check if user is in wheel/sudo group | Ensure `user_owner.groups` includes `user_sudo_group` or `sudo: true` for additional users |
| Role fails at "Assert supported operating system" | OS family not in `user_supported_os` list | Only Archlinux, Debian, RedHat, Void, Gentoo are supported |
| `visudo: /etc/sudoers.d/wheel: bad permissions` | File permissions are not 0440 | Role sets 0440 automatically. If changed externally, re-run the role |
| Password aging not applied | `chage -l <username>` -- check max/min/warn values | Ensure `user_manage_password_aging: true` and values are set in `user_owner` |
| Root lock assertion fails | `passwd -S root` -- check if root has a password | Lock root: `passwd -l root`. Or set `user_verify_root_lock: false` to skip |
| `chage -W` shows `changed` on first run | `chage -W` runs only when current warn age differs from desired value | Expected on first apply. Second run (idempotence) shows `ok` because the value already matches |
| Umask profile not applied after login | `/etc/profile.d/` only runs for login shells | Use `bash -l` or `su - <user>` to trigger profile scripts |

## Testing

Both scenarios are required. Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Logic correctness, idempotence, config deployment (Arch + Ubuntu) |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic, password aging, root lock | Real PAM, real shadow, Arch + Ubuntu matrix, password aging |

### Success criteria

- All steps complete: `syntax -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Assertions |
|----------|----------|------------|
| User existence | owner, extra, sudo user in passwd | 3 |
| Groups | owner in sudo group, extra NOT in sudo group, extra in video | 3 |
| Shadow | locked accounts, password aging (max/min/warn) | 9 |
| Umask | profile scripts exist with correct values and username guard | 6 |
| Sudoers | file exists (0440), syntax valid, group rule, timestamp_timeout, use_pty, logfile, passwd_timeout | 8 |
| Logrotate | config exists (0644), path, frequency, rotate count, compress, delaycompress | 8 |
| Absent users | `testuser_toberemoved` not in passwd | 1 |
| Root lock | `passwd -S root` shows `L` (Vagrant only) | 1 |
| Package | sudo installed via `package_facts` | 1 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `testuser_owner not found in passwd` | Converge did not create user | Check converge vars: `user_owner.name` must be `testuser_owner` |
| `shadow min_age not set` | Password aging disabled in Docker | Docker scenario sets `user_manage_password_aging=false` via extra-vars; Vagrant enables it |
| Idempotence failure on user creation | Password hash changes between runs | Ensure `update_password: on_create` (not `always`) in converge vars |
| `Root account is not locked` | Docker does not lock root by default | Docker scenario sets `user_verify_root_lock: false`; Vagrant prepare locks root |
| `visudo: command not found` | sudo package not installed | Check prepare.yml runs before converge |
| `video group does not exist` | Missing group in container | prepare.yml creates the `video` group before converge |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `user` | Entire role | Full apply: `ansible-playbook playbook.yml --tags user` |
| `sudo` | Sudo install + policy deployment | Re-deploy sudoers without touching users: `--tags sudo` |
| `install` | Package installation only | Install sudo package only: `--tags install` |
| `security` | CIS security checks + absent-user removal | Audit security posture: `--tags security` |
| `report` | Execution report output (requires `common` role) | Re-generate report: `--tags report` |
| `cis_5.3.4` | Sudo timestamp timeout task | Audit CIS 5.3.4 compliance |
| `cis_5.3.5` | Sudo use_pty task | Audit CIS 5.3.5 compliance |
| `cis_5.3.7` | Sudo logfile task | Audit CIS 5.3.7 compliance |
| `cis_5.4.1` | Password warn age (chage -W) | Audit CIS 5.4.1 compliance |
| `cis_5.4.2` | Umask profile deployment | Audit CIS 5.4.2 compliance |
| `cis_5.4.3` | Root lock verification | Audit CIS 5.4.3 compliance |
| `cis_5.5.1` | Password expire max | Audit CIS 5.5.1 compliance |
| `cis_5.5.2` | Password expire min | Audit CIS 5.5.2 compliance |

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No -- override via inventory |
| `vars/*.yml` | OS-family package mappings | Only when adding distro support |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/owner.yml` | Owner user creation + umask + aging | When changing owner setup logic |
| `tasks/additional_users.yml` | Additional user creation + sudo + umask | When changing additional user logic |
| `tasks/sudo.yml` | Sudoers + logrotate deployment | When changing sudo policy |
| `tasks/security.yml` | Root lock assertion (CIS 5.4.3) | When changing security checks |
| `tasks/verify.yml` | Post-deploy read-only verification | When changing verification logic |
| `tasks/install.yml` | Sudo package installation | Rarely |
| `templates/sudoers_hardening.j2` | Sudoers template | When adding sudo directives |
| `templates/sudo_logrotate.j2` | Logrotate template for sudo.log | When changing rotation policy |
| `templates/user_umask.sh.j2` | Per-user umask profile script | When changing umask deployment |
| `meta/main.yml` | Galaxy metadata | Rarely |
| `molecule/` | Test scenarios (docker, vagrant, shared) | When changing test coverage |
