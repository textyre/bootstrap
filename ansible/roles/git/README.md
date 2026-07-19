# git

Configures the Git developer toolchain for one or more existing users.

## Contract

The role owns:

- Git and Git LFS package installation.
- Global per-user Git configuration in each managed user's `~/.gitconfig`.
- Optional commit signing configuration for SSH or GPG signing.
- Optional aliases, credential helper, global hooks path, extra Git config, and safe directories.

The role does not create users, manage SSH/GPG keys, manage repositories, clone code, configure Git hosting accounts, or manage dotfiles outside its explicit Git config contract.

## Execution Flow

1. **Validate** (`tasks/validate.yml`) -- checks that a distro mapping exists for the detected OS family.
2. **Load vars** (`tasks/load_vars.yml`) -- loads `vars/distro/<os_family>/main.yml`.
3. **Configure** (`tasks/configure/main.yml`) -- installs packages and configures each managed user.
4. **Verify** (`tasks/verify.yml`) -- checks `git` and `git-lfs` binaries are usable.
5. **Report** -- renders the final execution report through the shared `common` role.

`tasks/main.yml` is only the orchestrator.

## Variables

Override these through inventory. Do not edit role defaults directly.

| Variable | Default | Description |
|----------|---------|-------------|
| `git_owner` | project `target_user` | Primary user dict. The user must already exist. |
| `git_additional_users` | `[]` | Additional user dicts managed by the role. |
| `git_default_branch` | `main` | Value for `init.defaultBranch`. |
| `git_editor` | `vim` | Value for `core.editor`. |
| `git_pull_rebase` | `true` | Value for `pull.rebase`. |
| `git_push_autosetup_remote` | `true` | Value for `push.autoSetupRemote`. |
| `git_core_autocrlf` | `input` | Value for `core.autocrlf`. |
| `git_manage_aliases` | `true` | Enables alias management. |
| `git_manage_credential` | `true` | Enables credential helper management. |
| `git_manage_hooks` | `false` | Enables global hooks directory and `core.hooksPath`. |
| `git_aliases_preset` | built-in aliases | Base alias map. |
| `git_aliases_extra` | `{}` | Additional aliases merged over presets. |
| `git_credential_helper` | `cache --timeout=3600` | Shared credential helper default. |
| `git_hooks_path` | `~/.config/git/hooks` | Global hooks directory. |
| `git_config_extra` | `{}` | Additional arbitrary Git config values. |
| `git_safe_directories` | `[]` | Paths added to `safe.directory`. |

User dict:

```yaml
git_owner:
  name: textyre
  user_name: "textyre"
  user_email: "textyre@example.com"
  signing_method: none
  signing_key: ""
  credential_helper: ""
```

Supported `signing_method` values are `none`, `ssh`, and `gpg`. `none` disables automatic commit signing. `ssh` and `gpg` enable automatic signing; for `ssh`, `signing_key` is a public-key path, and for `gpg`, it is a key ID.

## Internal Vars

| File | Purpose |
|------|---------|
| `vars/main.yml` | Supported OS families. |
| `vars/distro/archlinux/main.yml` | Arch package names. |
| `vars/distro/debian/main.yml` | Debian/Ubuntu package names. |
| `vars/distro/redhat/main.yml` | RedHat/Fedora package names. |
| `vars/distro/void/main.yml` | Void package names. |
| `vars/distro/gentoo/main.yml` | Gentoo package names. |

## Supported Platforms

| OS family | Git package | LFS package |
|-----------|-------------|-------------|
| Archlinux | `git` | `git-lfs` |
| Debian / Ubuntu | `git` | `git-lfs` |
| RedHat / Fedora | `git` | `git-lfs` |
| Void | `git` | `git-lfs` |
| Gentoo | `dev-vcs/git` | `dev-vcs/git-lfs` |

Git is a client-side tool. The role manages no service and has no init-system tasks.

## Examples

### Basic User

```yaml
git_owner:
  name: textyre
  user_name: "textyre"
  user_email: "textyre@example.com"
  signing_method: none
  signing_key: ""
  credential_helper: ""
```

### SSH Signing

```yaml
git_owner:
  name: textyre
  user_name: "textyre"
  user_email: "textyre@example.com"
  signing_method: ssh
  signing_key: "~/.ssh/id_ed25519.pub"
  credential_helper: ""
```

### Extra Config And Hooks

```yaml
git_manage_hooks: true
git_config_extra:
  color.ui: auto
  diff.colorMoved: zebra
git_aliases_extra:
  up: "pull --rebase --autostash"
git_safe_directories:
  - /opt/shared-repo
```

## Testing

The role has Docker and Vagrant Molecule scenarios.

| Scenario | What it proves |
|----------|----------------|
| Docker | Fast Arch/Ubuntu syntax, install, converge, and idempotence coverage. |
| Vagrant | Real Arch/Ubuntu VM syntax, converge, and idempotence coverage. |

The role itself verifies that both `git` and `git-lfs` are usable. Molecule checks that the role parses, converges in Docker and real VM environments, and is idempotent; it does not repeat role verification or test Git functionality.

## File Map

| File | Purpose |
|------|---------|
| `defaults/main.yml` | External role contract. |
| `vars/main.yml` | Internal supported OS constants. |
| `vars/distro/<os_family>/main.yml` | Distro package names. |
| `tasks/main.yml` | Orchestrator only. |
| `tasks/validate.yml` | Distro mapping validation. |
| `tasks/load_vars.yml` | Distro variable loading. |
| `tasks/configure/main.yml` | Configure pipeline. |
| `tasks/configure/install.yml` | Package installation. |
| `tasks/configure/user.yml` | Per-user configuration entrypoint. |
| `tasks/configure/base.yml` | Base Git config and safe directories. |
| `tasks/configure/extra.yml` | Additional arbitrary Git config. |
| `tasks/configure/signing.yml` | SSH/GPG signing config. |
| `tasks/configure/aliases.yml` | Alias config. |
| `tasks/configure/credential.yml` | Credential helper config. |
| `tasks/configure/lfs.yml` | Git LFS global filter config. |
| `tasks/verify.yml` | Final binary usability verification. |
| `molecule/` | Docker, Vagrant, and shared test scenarios. |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Unsupported OS failure | Host OS family is outside the supported set | Use Arch, Ubuntu/Debian, Fedora/RedHat, Void, or Gentoo. |
| `become_user` fails | Managed user does not exist | Create the user with the owning user role before this role. |
| Git LFS verify fails | LFS package is unavailable or not installed | Check distro package mapping and package repositories. |
| Expected Git config is overwritten later | Another role or dotfile manager writes `~/.gitconfig` after this role | Ensure ownership/order is explicit; this role owns only its configured Git keys. |
