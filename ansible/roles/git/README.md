# git

Git developer toolchain: install, global config, commit signing (SSH/GPG), aliases, credential helper, LFS, global hooks. Multi-user support with per-subsystem toggles.

## What this role does

- [x] Installs `git` and `git-lfs` (package name mapped per OS family)
- [x] Configures base git settings per user: `user.name`, `user.email`, `init.defaultBranch`, `core.editor`, `pull.rebase`, `push.autoSetupRemote`, `core.autocrlf`
- [x] Configures commit signing (SSH or GPG) with fail-fast validation
- [x] Applies preset + custom aliases (three-layer merge: preset → extra → overwrite)
- [x] Configures credential helper per user
- [x] Initializes git-lfs per user (`git lfs install --skip-repo`)
- [x] Creates global hooks directory and sets `core.hooksPath`
- [x] Applies arbitrary extra config via dict (`git_config_extra` + `git_config_overwrite`)
- [x] Sets `safe.directory` entries (CVE-2022-24765) with idempotent multi-value pattern
- [x] Multi-user: loops over `git_owner` + `git_additional_users`
- [x] In-role verification (`verify.yml`)
- [x] Dual logging via `common/report_phase.yml`

## Architecture

Two-level design:

1. **System layer** (root): install packages
2. **Per-user layer** (`become_user`): all configuration, loops over `[git_owner] + git_additional_users`

```
main.yml
├── Assert supported OS (ROLE-003)
├── Include OS vars (ROLE-001)
├── install.yml — git + git-lfs
├── configure_user.yml — per-user loop
│   ├── config_base.yml
│   ├── config_extra.yml
│   ├── signing.yml
│   ├── aliases.yml
│   ├── credential.yml
│   ├── lfs_user.yml
│   └── hooks directory + core.hooksPath
├── verify.yml (ROLE-005)
└── report_render (ROLE-008)
```

## Variables

### User config

| Variable | Default | Description |
|----------|---------|-------------|
| `git_owner` | `{name: SUDO_USER}` | Primary user dict (see structure below) |
| `git_additional_users` | `[]` | List of additional user dicts |

User dict structure:

```yaml
git_owner:
  name: username          # System username
  user_name: "Full Name"  # git user.name
  user_email: "a@b.com"   # git user.email
  signing_method: none     # none / ssh / gpg
  signing_key: ""          # SSH public key path or GPG key ID
  credential_helper: ""    # Per-user override (empty = use shared default)
```

### Shared defaults

| Variable | Default | Description |
|----------|---------|-------------|
| `git_default_branch` | `main` | `init.defaultBranch` |
| `git_editor` | `vim` | `core.editor` |
| `git_pull_rebase` | `true` | `pull.rebase` |
| `git_push_autosetup_remote` | `true` | `push.autoSetupRemote` |
| `git_core_autocrlf` | `input` | `core.autocrlf` |
| `git_commit_sign` | profile-aware | `commit.gpgSign` — `true` if `security` in `workstation_profiles` |
| `git_credential_helper` | `cache --timeout=3600` | Shared credential helper |
| `git_safe_directories` | `[]` | `safe.directory` entries (CVE-2022-24765) |

### Subsystem toggles (ROLE-010)

| Variable | Default | Description |
|----------|---------|-------------|
| `git_manage_signing` | profile-aware | Enable signing config — `true` if `developer` or `security` profile |
| `git_manage_aliases` | `true` | Enable alias management |
| `git_manage_credential` | `true` | Enable credential helper |
| `git_manage_hooks` | `false` | Enable global hooks directory |
| `git_lfs_enabled` | `true` | Install and init git-lfs |

### Aliases

| Variable | Default | Description |
|----------|---------|-------------|
| `git_aliases_preset` | `st`, `co`, `br`, `ci`, `lg`, `unstage`, `last`, `amend` | Built-in aliases |
| `git_aliases_extra` | `{}` | Additional aliases (merged on top of preset) |
| `git_aliases_overwrite` | `{}` | Override any alias (highest priority) |

### Extra config

| Variable | Default | Description |
|----------|---------|-------------|
| `git_config_extra` | `{}` | Arbitrary git config dict (`key: value`) |
| `git_config_overwrite` | `{}` | Override extra config (highest priority) |
| `git_hooks_path` | `~/.config/git/hooks` | Global hooks directory path |

## Profile behavior (ROLE-009)

| Profile | `git_manage_signing` | `git_commit_sign` |
|---------|---------------------|-------------------|
| (none) | `false` | `false` |
| `developer` | `true` | `false` |
| `security` | `true` | `true` |

## Supported platforms

Archlinux, Debian/Ubuntu, RedHat/Fedora, Void Linux, Gentoo

## Tags

| Tag | Scope |
|-----|-------|
| `git` | All tasks |
| `git`, `install` | Package installation only |
| `git`, `configure` | All per-user configuration |
| `git`, `signing` | Commit signing only |
| `git`, `hooks` | Global hooks directory only |
| `git`, `lfs` | Git LFS only |
| `git`, `verify` | In-role verification only |

## Example playbook

Basic:

```yaml
- role: git
  vars:
    git_owner:
      name: textyre
      user_name: "textyre"
      user_email: "textyre@example.com"
      signing_method: none
      signing_key: ""
      credential_helper: ""
```

SSH signing:

```yaml
- role: git
  vars:
    git_owner:
      name: textyre
      user_name: "textyre"
      user_email: "textyre@example.com"
      signing_method: ssh
      signing_key: "~/.ssh/id_ed25519.pub"
      credential_helper: ""
    git_commit_sign: true
    git_manage_signing: true
```

Multi-user with extras:

```yaml
- role: git
  vars:
    git_owner:
      name: textyre
      user_name: "textyre"
      user_email: "textyre@example.com"
      signing_method: none
      signing_key: ""
      credential_helper: ""
    git_additional_users:
      - name: alice
        user_name: "Alice"
        user_email: "alice@example.com"
        signing_method: gpg
        signing_key: "ABCD1234"
        credential_helper: "store"
    git_config_extra:
      color.ui: auto
      diff.colorMoved: zebra
      merge.conflictstyle: diff3
      rerere.enabled: "true"
    git_manage_hooks: true
    git_safe_directories:
      - /opt/shared-repo
```

## Dependencies

None. Users must exist before this role runs (see `user` role).

## Testing

Three Molecule scenarios share a common `molecule/shared/` directory containing `converge.yml` and `verify.yml`. All scenarios exercise identical assertions (22 checks covering package install, binary, base config, extra config, safe directories, aliases, credential helper, git-lfs, hooks, and gitconfig file existence).

### Scenarios

| Scenario | Driver | Platforms | User |
|----------|--------|-----------|------|
| `default` | localhost | Arch Linux (local) | `$USER` |
| `docker` | Docker | Arch Linux (systemd container) | `root` |
| `vagrant` | Vagrant/libvirt | Arch Linux + Ubuntu 24.04 | `vagrant` |

### Running tests

```bash
cd ansible/roles/git

# Default scenario (localhost, current machine)
molecule test -s default

# Docker scenario (requires Docker + Arch systemd image)
molecule test -s docker

# Vagrant scenario (requires Vagrant + libvirt)
molecule test -s vagrant
```

### Molecule structure

```
molecule/
  shared/
    converge.yml    # Applied by all scenarios (no vault, no OS assertion)
    verify.yml      # 22 assertions, variable-driven, cross-platform
  default/
    molecule.yml    # localhost driver
  docker/
    molecule.yml    # Docker driver (Arch systemd)
    prepare.yml     # pacman cache update
  vagrant/
    molecule.yml    # Vagrant driver (Arch + Ubuntu)
    prepare.yml     # Python bootstrap, keyring refresh, apt cache
```
