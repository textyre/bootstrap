# shell

Installs Bash, Zsh, or Fish and assigns it as the login shell for an existing user.

The role does not create users and does not manage PATH, environment variables, or dotfiles. User-specific shell configuration remains the responsibility of Chezmoi/dotfiles.

## Execution flow

1. **Validate** (`tasks/validate.yml`) checks the supported OS family and selected shell.
2. **Load variables** (`tasks/load_vars.yml`) loads package and executable mappings for the detected OS family.
3. **Detect** (`tasks/detect.yml`) requires `shell_user` to reference an existing account.
4. **Configure** (`tasks/configure/main.yml`) installs the selected shell and assigns it to the account.
5. **Verify** (`tasks/verify.yml`) starts the configured executable with `--version`.
6. **Report** (`tasks/main.yml`) renders the execution report through the `common` role.

The role has no handlers and manages no service.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `shell_user` | project `target_user` | Existing account whose login shell is managed. |
| `shell_type` | `zsh` | Shell to install and assign: `bash`, `zsh`, or `fish`. |

Internal distro files define only package names and executable paths:

| OS family | Bash | Zsh | Fish |
|-----------|------|-----|------|
| Arch Linux | `bash` | `zsh` | `fish` |
| Ubuntu / Debian | `bash` | `zsh` | `fish` |
| Fedora / RedHat | `bash` | `zsh` | `fish` |
| Void Linux | `bash` | `zsh` | `fish` |
| Gentoo | `app-shells/bash` | `app-shells/zsh` | `app-shells/fish` |

## Example

```yaml
# ansible/inventory/group_vars/all/system.yml
shell_user: "{{ target_user }}"
shell_type: zsh
```

## Result

After the role completes:

- the selected shell executable is installed;
- the existing account's login-shell field points to that executable;
- new login sessions use the selected shell.

Existing sessions keep their current shell until the user logs in again. The role does not write `/etc/profile.d`, system `zshenv`, Fish `conf.d`, or files in the user's home directory.

## Testing

Docker and Vagrant scenarios run defaults-only converge and idempotence on Arch and Ubuntu. Shared prepare creates the target account because account creation belongs outside this role. The role-level verify phase checks that the selected shell executable starts.

All Ansible, lint, and Molecule operations run through the project remote VM or CI workflow.

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Target-user lookup fails | `shell_user` does not exist | Create the account through the owning user-management role or select an existing account. |
| New login still uses the old shell | The session started before the account entry changed | End the session and log in again. |
| PATH or dotfiles are missing | They are outside the shell role contract | Configure them through Chezmoi/dotfiles. |

## File map

| Path | Purpose |
|------|---------|
| `tasks/main.yml` | Phase orchestrator |
| `tasks/validate.yml` | Input validation |
| `tasks/load_vars.yml` | Distro mapping loader |
| `tasks/detect.yml` | Existing-account lookup |
| `tasks/configure/install.yml` | Shell package state |
| `tasks/configure/login_shell.yml` | Account login-shell state |
| `tasks/verify.yml` | Shell executable check |
| `vars/distro/` | Package and executable mappings |
| `molecule/shared/` | Shared prepare and converge playbooks |
