# git role

Configures Git across all managed workstations: installs packages and git-lfs,
sets global user config (name, email, default branch, editor), manages commit
signing (SSH or GPG), deploys aliases with three-layer merge, configures
credential helpers, creates global hooks directories, and applies arbitrary
extra config. Supports a primary owner user plus optional additional users, with
per-subsystem toggles and profile-aware defaults.

## Variables

### Owner configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `git_owner.name` | `SUDO_USER` or current user | Unix username for the primary user |
| `git_owner.user_name` | `""` | `user.name` in gitconfig (skipped if empty) |
| `git_owner.user_email` | `""` | `user.email` in gitconfig (skipped if empty) |
| `git_owner.signing_method` | `none` | `none`, `ssh`, or `gpg` |
| `git_owner.signing_key` | `""` | SSH public key path or GPG key ID |
| `git_owner.credential_helper` | `""` | Per-user override (falls back to `git_credential_helper`) |

### Additional users

| Variable | Default | Description |
|----------|---------|-------------|
| `git_additional_users` | `[]` | List of dicts with same keys as `git_owner` |

Each entry accepts the same fields as `git_owner` (`name`, `user_name`, `user_email`, `signing_method`, `signing_key`, `credential_helper`).

### Shared defaults

Applied to all users (owner + additional).

| Variable | Default | Description |
|----------|---------|-------------|
| `git_default_branch` | `main` | `init.defaultBranch` |
| `git_editor` | `vim` | `core.editor` |
| `git_pull_rebase` | `true` | `pull.rebase` |
| `git_push_autosetup_remote` | `true` | `push.autoSetupRemote` |
| `git_core_autocrlf` | `input` | `core.autocrlf` |
| `git_commit_sign` | `true` if `security` profile, else `false` | `commit.gpgSign` |

### Per-subsystem toggles

| Variable | Default | Description |
|----------|---------|-------------|
| `git_manage_signing` | `true` if `developer` or `security` profile | Run signing configuration tasks |
| `git_manage_aliases` | `true` | Deploy git aliases |
| `git_manage_credential` | `true` | Configure credential helper |
| `git_manage_hooks` | `false` | Create global hooks directory and set `core.hooksPath` |
| `git_lfs_enabled` | `true` | Install git-lfs and run `git lfs install --skip-repo` per user |

### Aliases

Three-layer merge: `preset` -> `extra` -> `overwrite`. Later layers win on conflict.

| Variable | Default | Description |
|----------|---------|-------------|
| `git_aliases_preset` | `{st, co, br, ci, lg, unstage, last, amend}` | Built-in convenience aliases |
| `git_aliases_extra` | `{}` | Additional aliases merged on top of preset |
| `git_aliases_overwrite` | `{}` | Final overrides (replaces any key from preset or extra) |

**Preset aliases:**

| Alias | Expansion |
|-------|-----------|
| `st` | `status` |
| `co` | `checkout` |
| `br` | `branch` |
| `ci` | `commit` |
| `lg` | `log --graph --pretty=format:...` (compact graph) |
| `unstage` | `reset HEAD --` |
| `last` | `log -1 HEAD` |
| `amend` | `commit --amend --no-edit` |

### Credential helper

| Variable | Default | Description |
|----------|---------|-------------|
| `git_credential_helper` | `cache --timeout=3600` | Default credential helper (per-user override via `git_owner.credential_helper`) |

### Global hooks

| Variable | Default | Description |
|----------|---------|-------------|
| `git_hooks_path` | `~/.config/git/hooks` | Path set in `core.hooksPath`; directory created by the role |

The hooks directory is created with `0755` permissions. Hook scripts themselves are deployed by dotfiles/chezmoi, not this role.

### Extra git config

| Variable | Default | Description |
|----------|---------|-------------|
| `git_config_extra` | `{}` | Dict of arbitrary `key: value` pairs applied to gitconfig |
| `git_config_overwrite` | `{}` | Overrides merged on top of `git_config_extra` |

Keys are full git config names (e.g., `merge.conflictstyle`, `diff.algorithm`).

### Safe directory

| Variable | Default | Description |
|----------|---------|-------------|
| `git_safe_directories` | `[]` | List of paths added to `safe.directory` (CVE-2022-24765 mitigation) |

## Profile Behavior

| Setting | No profile | `developer` | `security` | `developer` + `security` |
|---------|-----------|-------------|------------|--------------------------|
| `git_manage_signing` | `false` | `true` | `true` | `true` |
| `git_commit_sign` | `false` | `false` | `true` | `true` |

`security` profile forces `commit.gpgSign=true` for all commits. The `developer` profile enables signing configuration tasks but does not force signing unless `security` is also active.

All other variables are profile-independent and use their defaults regardless of active profiles.

## Usage Examples

### Basic (just name and email)

```yaml
git_owner:
  name: textyre
  user_name: "Textyre"
  user_email: "textyre@example.com"
```

### SSH signing

```yaml
git_owner:
  name: textyre
  user_name: "Textyre"
  user_email: "textyre@example.com"
  signing_method: ssh
  signing_key: "~/.ssh/id_ed25519.pub"

git_commit_sign: true
```

### GPG signing

```yaml
git_owner:
  name: textyre
  user_name: "Textyre"
  user_email: "textyre@example.com"
  signing_method: gpg
  signing_key: "ABCDEF1234567890"

git_commit_sign: true
```

### Multi-user with additional_users

```yaml
git_owner:
  name: textyre
  user_name: "Textyre"
  user_email: "textyre@example.com"
  signing_method: ssh
  signing_key: "~/.ssh/id_ed25519.pub"

git_additional_users:
  - name: alice
    user_name: "Alice"
    user_email: "alice@example.com"
    signing_method: none
  - name: bob
    user_name: "Bob"
    user_email: "bob@example.com"
    signing_method: gpg
    signing_key: "DEADBEEF"
```

### Custom aliases

```yaml
# Add extra aliases on top of presets
git_aliases_extra:
  dc: "diff --cached"
  wip: "commit -am 'WIP'"

# Override a preset alias
git_aliases_overwrite:
  lg: "log --oneline --graph --decorate"
```

### Extra config

```yaml
git_config_extra:
  merge.conflictstyle: diff3
  diff.algorithm: histogram
  rerere.enabled: "true"
  fetch.prune: "true"

# Store-based credential helper instead of cache
git_credential_helper: store

# Safe directories for shared repos
git_safe_directories:
  - /opt/shared-repo
  - /srv/project
```

## Tags

| Tag | What it runs |
|-----|-------------|
| `git` | Everything (all tasks) |
| `install` | Package installation (git, git-lfs) |
| `configure` | Base gitconfig + extra config (all users) |
| `signing` | SSH/GPG signing configuration |
| `aliases` | Git alias deployment |
| `credential` | Credential helper configuration |
| `hooks` | Global hooks directory + `core.hooksPath` |
| `lfs` | git-lfs installation and per-user init |
| `security` | `safe.directory` configuration |
| `report` | Reporting tasks only |

## Dependencies

None. The role is self-contained.

`community.general` collection required for `community.general.git_config` (listed in `ansible/requirements.yml`).

The `user` role should run before `git` to ensure user accounts exist. The roles are independent but typically ordered in the playbook so that `user` precedes `git`.
