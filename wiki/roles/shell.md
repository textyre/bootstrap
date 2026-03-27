# Role: shell

**Phase**: 2 | **Category**: Environment

## Purpose

System-level shell environment setup. Installs the chosen shell (bash/zsh/fish), sets the user's login shell, creates XDG Base Directory structure, and deploys global configuration files (/etc/profile.d/, /etc/zsh/zshenv, /etc/fish/conf.d/). Per-user dotfiles (.bashrc, .zshrc) are managed by chezmoi, not this role.

## Key Variables (defaults)

```yaml
# Supported OS families (ROLE-003)
_shell_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# Target user
shell_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"

# Shell type: bash | zsh | fish
shell_type: zsh  # Profile-aware: developer -> zsh, base -> zsh

# --- Subsystem toggles (ROLE-010) ---
shell_manage_packages: true       # Install shell packages
shell_set_login: true             # Set as user's login shell via chsh
shell_manage_xdg: true            # Create XDG Base Directories
shell_manage_global_config: true  # Deploy global config files
shell_zsh_zdotdir: true           # Set ZDOTDIR in /etc/zsh/zshenv (zsh only)

# --- Path and env configuration ---
# Profile-aware: developer includes cargo, go; base only .local/bin
shell_global_path:
  - "$HOME/.local/bin"    # always
  - "$HOME/.cargo/bin"    # developer profile
  - "/usr/local/go/bin"   # developer profile

shell_global_env: {}
#   GOPATH: "$HOME/go"    # developer profile

# User overrides merged on top of shell_global_env (ROLE-010)
shell_global_env_overwrite: {}

# XDG Base Directories to create
shell_xdg_dirs:
  - ".config"
  - ".local/share"
  - ".local/bin"
  - ".cache"
```

## What It Configures

- **Packages**: Installs shell package for the chosen `shell_type` (per-distro vars)
- **Login shell**: Sets the user's default login shell via `ansible.builtin.user`
- **XDG directories**: Creates `~/.config`, `~/.local/share`, `~/.local/bin`, `~/.cache` with correct ownership
- **Global config files**:
  - `/etc/profile.d/dev-paths.sh` (bash + zsh) -- PATH additions and env vars
  - `/etc/zsh/zshenv` (zsh only) -- ZDOTDIR pointing to XDG path
  - `/etc/fish/conf.d/dev-paths.fish` (fish only) -- PATH and env for fish

## Workstation Profiles (ROLE-009)

| Setting | base | developer |
|---------|------|-----------|
| `shell_type` | zsh | zsh |
| `shell_global_path` | `[.local/bin]` | `[.local/bin, .cargo/bin, /usr/local/go/bin]` |
| `shell_global_env` | `{}` | `{GOPATH: $HOME/go}` |

All profile-dependent settings use `workstation_profiles | default([])` for safe fallback when profiles are undefined.

## Dependencies

- `common` -- used for `report_phase.yml` and `report_render.yml`

## Tags

- `shell` -- all tasks
- `shell:install` -- package installation
- `shell:configure` -- login shell, XDG, global config
- `shell:report` -- execution report
- `profile:developer` -- developer profile-specific settings

---

Back to [[Home]]
