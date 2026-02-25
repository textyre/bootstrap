# shell

System-level shell environment. Installs the shell package, sets the login shell, creates XDG Base Directories, and deploys global configuration files. Per-user dotfiles (`.bashrc`, `.zshrc`, etc.) are managed by chezmoi — **not this role**.

## What this role does

- [x] Validates configuration (`shell_type`, `shell_user`, OS family)
- [x] Installs shell package (`zsh`, `fish`, or no-op for bash — package name mapped per OS family)
- [x] Sets login shell for `shell_user` via `ansible.builtin.user` when `shell_set_login: true`
- [x] Creates XDG Base Directories (`~/.config`, `~/.local/share`, `~/.local/bin`, `~/.cache`)
- [x] Deploys `/etc/profile.d/dev-paths.sh` (bash + zsh) with PATH additions and env vars
- [x] Deploys `/etc/zsh/zshenv` (zsh only) setting `ZDOTDIR` to XDG config path
- [x] Deploys `/etc/fish/conf.d/dev-paths.fish` (fish only) with PATH additions and env vars
- [x] Verifies configuration after apply (login shell, XDG dirs, config files)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `shell_user` | `SUDO_USER` or current user | Target user for login shell and XDG dirs |
| `shell_type` | `zsh` | Shell to install: `bash`, `zsh`, or `fish` |
| `shell_set_login` | `true` | Set as login shell via `ansible.builtin.user` |
| `shell_global_path` | `~/.local/bin`, `~/.cargo/bin`, `/usr/local/go/bin` | PATH entries added to global profile |
| `shell_global_env` | `{}` | Environment variables added to global profile (e.g. `GOPATH`) |
| `shell_xdg_dirs` | `.config`, `.local/share`, `.local/bin`, `.cache` | XDG directories to create under `shell_user` home |
| `shell_zsh_zdotdir` | `true` | Set `ZDOTDIR` in `/etc/zsh/zshenv` pointing to `$XDG_CONFIG_HOME/zsh` |

## Supported platforms

Arch Linux, Debian, Ubuntu, RedHat/EL, Void Linux, Gentoo

## Tags

`shell`, `shell,report`

Use `--skip-tags report` in molecule and automation pipelines to suppress the execution report.

## Molecule scenarios

| Scenario | Driver | Platforms | Notes |
|----------|--------|-----------|-------|
| `default` | localhost (unmanaged) | local machine | Syntax + converge + idempotence + verify |
| `docker` | Docker | Arch Linux systemd container | Full test sequence with container |
| `vagrant` | libvirt | Arch Linux VM + Ubuntu Noble VM | Cross-platform, tests real non-root user |

All scenarios share `molecule/shared/converge.yml` and `molecule/shared/verify.yml`.

## Notes

- The role only manages **system-level** files (`/etc/profile.d/`, `/etc/zsh/zshenv`, `/etc/fish/conf.d/`). Per-user dotfiles are chezmoi's domain.
- In Docker containers the role runs as `root` (no `SUDO_USER`). XDG dirs are created under `/root/`. The Vagrant scenario provides a realistic non-root `vagrant` user.
- Gentoo uses `app-shells/zsh` / `app-shells/fish` as package names; all other distros use `zsh` / `fish`.
