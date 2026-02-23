# Shell Role Redesign

> Focused system-level shell environment — install, login shell, XDG dirs, global config.

## Problem

The shell role is functionally disabled. `shell_deploy_config: false` because chezmoi manages
dotfiles. The role only installs a shell package, creates `~/.local/bin`, and prints a debug
message. Templates are deprecated. Fails ROLE-001, 003, 005, 008, 010 standards.

## Decision

**Approach A: Focused "System Shell Environment."** The role handles system-level shell setup
that chezmoi cannot: package installation, login shell assignment, XDG directory creation,
and global config (`/etc/profile.d/`, `/etc/zsh/zshenv`, `/etc/fish/conf.d/`).

Rejected alternatives:
- **B (Developer Terminal Experience):** scope creep — terminal utilities are packages, not shell config
- **C (Delete and scatter):** shell logic scattered across 3-4 roles, harder to debug

## Shell vs vconsole

- **vconsole** — TTY/virtual console (tty1-tty6): keymap layout, console font, GPM mouse.
  The raw Linux framebuffer terminal before any graphical environment.
- **shell** — command interpreter (bash/zsh/fish) running inside any terminal emulator, TTY, or SSH.
  The interactive command-line experience itself.

## Scope

### Responsibilities

| # | Task | Description |
|---|------|-------------|
| 1 | INSTALL | Shell package via OS-specific dispatch (`ansible.builtin.package`) |
| 2 | CHSH | Set user's login shell (`ansible.builtin.user: shell=`) |
| 3 | XDG_DIRS | Create `~/.config`, `~/.local/share`, `~/.local/bin`, `~/.cache` |
| 4 | GLOBAL | Deploy `/etc/profile.d/dev-paths.sh` (bash/zsh), `/etc/fish/conf.d/dev-paths.fish` (fish), `/etc/zsh/zshenv` (zsh) |
| 5 | VERIFY | Assert login shell, directories, global config files |

### Supported shells

- **bash** — `/etc/profile.d/` for global config
- **zsh** — `/etc/profile.d/` + `/etc/zsh/zshenv` for ZDOTDIR
- **fish** — `/etc/fish/conf.d/` for global config (different syntax)

### Removed (chezmoi territory)

- `templates/bashrc.j2` — deprecated
- `templates/zshrc.j2` — unused
- `shell_deploy_config`, `shell_aliases`, `shell_env_vars`, `shell_history_size`, `shell_histcontrol`

## File Structure

```
roles/shell/
├── defaults/main.yml
├── vars/
│   ├── main.yml                   # _shell_supported_os
│   ├── archlinux.yml              # _shell_packages, _shell_bin
│   ├── debian.yml
│   ├── redhat.yml
│   ├── void.yml
│   └── gentoo.yml
├── meta/main.yml
├── handlers/main.yml              # empty — no services
├── tasks/
│   ├── main.yml                   # Orchestrator
│   ├── validate.yml               # Preflight assertions
│   ├── install.yml                # Install shell package
│   ├── chsh.yml                   # Set login shell
│   ├── xdg.yml                    # Create XDG directories
│   ├── global.yml                 # Deploy global config
│   └── verify.yml                 # Assert applied state
├── templates/
│   ├── profile.d-dev-paths.sh.j2  # /etc/profile.d/ (bash/zsh)
│   ├── zshenv.j2                  # /etc/zsh/zshenv
│   └── fish-dev-paths.fish.j2     # /etc/fish/conf.d/ (fish)
└── molecule/
    └── default/
        ├── molecule.yml
        ├── converge.yml
        └── verify.yml
```

## Variables

```yaml
# === System-level shell environment ===

shell_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
shell_type: zsh                  # bash | zsh | fish
shell_set_login: true            # Set as login shell via chsh?

# System-wide PATH additions → /etc/profile.d/ or /etc/fish/conf.d/
shell_global_path:
  - "$HOME/.local/bin"
  - "$HOME/.cargo/bin"
  - "/usr/local/go/bin"

# System-wide env vars → same files
shell_global_env: {}
#   GOPATH: "$HOME/go"
#   JAVA_HOME: "/usr/lib/jvm/default"

# XDG directories to create
shell_xdg_dirs:
  - "{{ _shell_user_home }}/.config"
  - "{{ _shell_user_home }}/.local/share"
  - "{{ _shell_user_home }}/.local/bin"
  - "{{ _shell_user_home }}/.cache"

# Set ZDOTDIR in /etc/zsh/zshenv? (zsh only)
shell_zsh_zdotdir: true
```

## Task Flow

```
validate.yml   → Assert OS family, shell_type ∈ [bash, zsh, fish]
    ↓
install.yml    → ansible.builtin.package: {{ _shell_packages }}
    ↓
chsh.yml       → ansible.builtin.user: shell={{ _shell_bin }}  (when shell_set_login)
    ↓
xdg.yml        → ansible.builtin.file: state=directory for each XDG dir
    ↓
global.yml     → template: profile.d-dev-paths.sh.j2 → /etc/profile.d/dev-paths.sh
                  template: zshenv.j2 → /etc/zsh/zshenv           (when zsh)
                  template: fish-dev-paths.fish.j2 → /etc/fish/conf.d/  (when fish)
    ↓
verify.yml     → Assert login shell, dirs, config files
    ↓
report         → report_phase.yml + report_render.yml
```

## Templates

### profile.d-dev-paths.sh.j2

```bash
# {{ ansible_managed }}
# System-wide PATH additions for development toolchains
{% for dir in shell_global_path %}
[ -d "{{ dir }}" ] && case ":$PATH:" in *":{{ dir }}:"*) ;; *) PATH="{{ dir }}:$PATH" ;; esac
{% endfor %}
export PATH
{% for key, value in shell_global_env.items() %}
export {{ key }}="{{ value }}"
{% endfor %}
```

### fish-dev-paths.fish.j2

```fish
# {{ ansible_managed }}
# System-wide PATH additions for development toolchains
{% for dir in shell_global_path %}
if test -d "{{ dir }}"
    fish_add_path --global "{{ dir }}"
end
{% endfor %}
{% for key, value in shell_global_env.items() %}
set -gx {{ key }} "{{ value }}"
{% endfor %}
```

### zshenv.j2

```bash
# {{ ansible_managed }}
# Global zsh environment — loaded for ALL zsh sessions
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
```

## Standards Compliance

| Req | Status | How |
|-----|--------|-----|
| ROLE-001 | Fixed | `vars/{archlinux,debian,redhat,void,gentoo}.yml` + `ansible.builtin.package` |
| ROLE-002 | N/A | No services managed |
| ROLE-003 | Fixed | `_shell_supported_os` list + preflight assert |
| ROLE-004 | N/A | Not security-relevant |
| ROLE-005 | Fixed | `verify.yml` — login shell check, dir stat, config slurp+assert |
| ROLE-006 | Fixed | `molecule/default/verify.yml` tests applied state |
| ROLE-007 | N/A | Not a system role |
| ROLE-008 | Fixed | `report_phase.yml` per step + `report_render.yml` at end |
| ROLE-009 | Deferred | No profile-specific behavior needed yet |
| ROLE-010 | Fixed | Per-subsystem toggles: `shell_set_login`, `shell_zsh_zdotdir`, `shell_global_path` |
| ROLE-011 | Fixed | FQCN, `ansible.builtin.user` for chsh, no shell hacks |

## OS Package Map

| Distro | bash | zsh | fish |
|--------|------|-----|------|
| Archlinux | (preinstalled) | zsh | fish |
| Debian | (preinstalled) | zsh | fish |
| RedHat | (preinstalled) | zsh | fish |
| Void | (preinstalled) | zsh | fish |
| Gentoo | (preinstalled) | app-shells/zsh | app-shells/fish |

Shell binary paths: bash → `/bin/bash`, zsh → `/bin/zsh` or `/usr/bin/zsh`, fish → `/usr/bin/fish`.
Use `command -v {{ shell_type }}` or lookup from vars file.
