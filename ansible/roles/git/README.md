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

## Execution flow

1. **Preflight** — asserts the OS family is one of the 5 supported distros (Archlinux, Debian, RedHat, Void, Gentoo). Fails immediately if unsupported.
2. **Load OS variables** — includes `vars/<os_family>.yml` to resolve package names (`git_packages`, `git_lfs_package`) for the detected OS family.
3. **Install** (`tasks/install.yml`) — installs `git` via package manager. Installs `git-lfs` if `git_lfs_enabled` is true. Skips LFS package gracefully if toggle is false.
4. **Configure users** (`tasks/configure_user.yml`) — loops over `[git_owner] + git_additional_users`, running all per-user configuration as `become_user`. For each user:
   - 4a. **Base config** (`tasks/config_base.yml`) — sets `user.name`, `user.email`, `init.defaultBranch`, `core.editor`, `pull.rebase`, `push.autoSetupRemote`, `core.autocrlf` via `community.general.git_config`. Adds `safe.directory` entries (CVE-2022-24765) idempotently.
   - 4b. **Extra config** (`tasks/config_extra.yml`) — applies arbitrary key-value pairs from `git_config_extra | combine(git_config_overwrite)`. Skipped if both dicts are empty.
   - 4c. **Signing** (`tasks/signing.yml`) — validates `signing_key` is set when `signing_method` is `ssh` or `gpg`. Fails if key is empty. Sets `gpg.format`, `user.signingKey`, `commit.gpgSign`. Skipped if `git_manage_signing` is false.
   - 4d. **Aliases** (`tasks/aliases.yml`) — merges three layers: `git_aliases_preset` + `git_aliases_extra` + `git_aliases_overwrite`. Sets each as `alias.<name>`. Skipped if `git_manage_aliases` is false.
   - 4e. **Credential** (`tasks/credential.yml`) — sets `credential.helper` per user (user-level override or shared default). Skipped if `git_manage_credential` is false.
   - 4f. **LFS init** (`tasks/lfs_user.yml`) — runs `git lfs install --skip-repo` to register LFS hooks in the user's gitconfig. Skipped if `git_lfs_enabled` is false.
   - 4g. **Hooks** — creates `git_hooks_path` directory (`~/.config/git/hooks` by default) and sets `core.hooksPath`. Skipped if `git_manage_hooks` is false.
5. **Verify** (`tasks/verify.yml`) — checks `git --version`, verifies `user.name` matches expected for owner, validates `commit.gpgSign` if signing is enabled, checks `git lfs version` if LFS is enabled, asserts hooks directory exists if hooks are managed. Fails with descriptive messages on mismatch.
6. **Report** — writes execution report via `common/report_phase.yml` and `common/report_render.yml` for structured output.

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

## Logs

Git is a client-side tool — it does not produce log files or run a service. All output is from Ansible execution.

### Ansible output

| Source | How to access | Contents |
|--------|--------------|----------|
| Execution report | Ansible stdout (last task) | Structured phase report: preflight, install, configure users, verify |
| Per-task output | Ansible stdout with `-v` flag | Individual `community.general.git_config` results, assertion messages |
| JSON report fact | `_git_phases` Ansible fact | Machine-readable phase data for CI/CD pipelines |

### Reading the output

- Verification failure: look for `FAILED` lines in the verify phase — `fail_msg` shows expected vs actual values
- Signing misconfiguration: the `Assert commit signing is enabled` task shows the expected `commit.gpgSign` value and what was found
- Safe directory changes: `CVE-2022-24765 | Add git safe.directory entries` tasks report `changed` when new entries are added

### Log rotation

Not applicable — git does not produce persistent log files. Ansible output is ephemeral unless captured by CI/CD.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in the supported list | Check `ansible_facts['os_family']` — must be one of: Archlinux, Debian, RedHat, Void, Gentoo |
| `signing_method=ssh but signing_key is empty` | User dict has `signing_method: ssh` but no `signing_key` | Set `signing_key` to the SSH public key path (e.g., `~/.ssh/id_ed25519.pub`) |
| `git user.name mismatch` in verify | `user.name` in gitconfig does not match `git_owner.user_name` | Check if another tool or dotfile overwrites `~/.gitconfig` after the role runs |
| `git lfs version` fails in verify | git-lfs package not installed | Ensure `git_lfs_enabled: true` (default) and the package name is correct in `vars/<os_family>.yml` |
| Aliases not applied | `git_manage_aliases` is false | Set `git_manage_aliases: true` in inventory. Check three-layer merge order: preset < extra < overwrite |
| `credential.helper` not set | Per-user override is empty and shared default was changed | Check `_git_current_user.credential_helper` and `git_credential_helper` — first non-empty wins |
| Hooks directory missing after role run | `git_manage_hooks` defaults to `false` | Set `git_manage_hooks: true` in inventory to enable global hooks |
| Safe directory entries duplicated | Multiple runs with different `git_safe_directories` lists | Role checks existing entries idempotently — duplicates indicate manual edits to `~/.gitconfig` |

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

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings: user, toggles, aliases, credential, hooks, extra config | No — override via inventory (`group_vars/` or `host_vars/`) |
| `vars/archlinux.yml` | Arch Linux package names | Only when changing Arch package names |
| `vars/debian.yml` | Debian/Ubuntu package names | Only when changing Debian package names |
| `vars/redhat.yml` | RedHat/Fedora package names | Only when changing RedHat package names |
| `vars/void.yml` | Void Linux package names | Only when changing Void package names |
| `vars/gentoo.yml` | Gentoo package names | Only when changing Gentoo package names |
| `tasks/main.yml` | Execution flow orchestrator — preflight, install, user loop, verify, report | When adding/removing execution phases |
| `tasks/install.yml` | Package installation (git + git-lfs) | Rarely — package names come from vars |
| `tasks/configure_user.yml` | Per-user configuration dispatcher — includes all config subtasks | When adding new per-user subsystems |
| `tasks/config_base.yml` | Core git settings (user.name, editor, safe.directory, etc.) | When adding new base config keys |
| `tasks/config_extra.yml` | Arbitrary config from `git_config_extra` dict | Rarely |
| `tasks/signing.yml` | SSH and GPG commit signing configuration | When changing signing logic |
| `tasks/aliases.yml` | Three-layer alias merge and apply | Rarely |
| `tasks/credential.yml` | Credential helper configuration | Rarely |
| `tasks/lfs_user.yml` | Per-user `git lfs install --skip-repo` | Rarely |
| `tasks/verify.yml` | Post-deploy self-checks (ROLE-005) | When adding new verification assertions |
| `meta/main.yml` | Role metadata (Galaxy info, dependencies) | When changing role metadata |
| `molecule/` | Test scenarios (default, docker, vagrant) | When changing test coverage |
