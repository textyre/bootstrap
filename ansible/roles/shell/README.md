# shell

Sets up the system-level shell environment: installs the shell package, sets the login shell, creates XDG Base Directories, and deploys global configuration files.

## Execution flow

1. **Resolve user home** (`tasks/main.yml`) -- looks up `shell_user` in `/etc/passwd` via `getent` to determine the home directory for XDG and ownership operations
2. **Load OS-specific vars** (`tasks/main.yml`) -- includes `vars/<os_family>.yml` to resolve package names (`shell_packages`) and binary paths (`shell_bin`) for the current distro
3. **Validate** (`tasks/validate.yml`) -- asserts OS family is supported, `shell_type` is one of `bash`/`zsh`/`fish`, and `shell_user` is defined and non-empty. Fails early with descriptive messages if any check fails
4. **Install** (`tasks/install.yml`) -- installs the shell package via `ansible.builtin.package`. Skips if `shell_type` is `bash` (already present on all distros)
5. **Set login shell** (`tasks/chsh.yml`) -- sets `shell_user`'s login shell via `ansible.builtin.user`. Skips when `shell_set_login: false`
6. **Create XDG directories** (`tasks/xdg.yml`) -- creates `~/.config`, `~/.local/share`, `~/.local/bin`, `~/.cache` under `shell_user`'s home with correct ownership
7. **Deploy global config** (`tasks/global.yml`) -- deploys system-wide shell configuration:
   - `/etc/profile.d/dev-paths.sh` (bash + zsh) -- PATH additions and environment variables
   - `/etc/zsh/zshenv` (zsh only) -- sets `ZDOTDIR` to `${XDG_CONFIG_HOME:-$HOME/.config}/zsh`
   - `/etc/fish/conf.d/dev-paths.fish` (fish only) -- PATH additions and environment variables via `fish_add_path`
8. **Verify** (`tasks/verify.yml`) -- checks login shell is correct (via `getent`), XDG dirs exist, and deployed config files are present
9. **Report** (`tasks/main.yml`) -- renders execution report via `common/report_render.yml`

### Handlers

This role has no handlers. It does not manage any services -- shell configuration is applied statically via config files and `passwd` entry.

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `shell_user` | `SUDO_USER` or current user | careful | Target user for login shell and XDG directories. Changing this affects which user's home directory is modified and which user's login shell is set |
| `shell_type` | `zsh` | safe | Shell to install and configure: `bash`, `zsh`, or `fish` |
| `shell_set_login` | `true` | safe | Whether to set `shell_type` as the user's login shell via `ansible.builtin.user` |
| `shell_global_path` | `["$HOME/.local/bin", "$HOME/.cargo/bin", "/usr/local/go/bin"]` | safe | PATH entries added to `/etc/profile.d/dev-paths.sh` or `/etc/fish/conf.d/dev-paths.fish` |
| `shell_global_env` | `{}` | safe | Environment variables added to global profile (e.g., `GOPATH: "$HOME/go"`) |
| `shell_xdg_dirs` | `[".config", ".local/share", ".local/bin", ".cache"]` | careful | XDG directories to create under `shell_user`'s home. Removing entries does not delete existing directories |
| `shell_zsh_zdotdir` | `true` | safe | Set `ZDOTDIR` in `/etc/zsh/zshenv` pointing to `${XDG_CONFIG_HOME:-$HOME/.config}/zsh`. Only applies when `shell_type: zsh` |

### Internal mappings (`vars/`)

These files contain per-distro package names and binary paths. Do not override via inventory -- edit the files directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | Supported OS families list (`shell_supported_os`) and supported shell types list (`shell_supported_types`) | Adding a new OS family or shell type |
| `vars/archlinux.yml` | Arch Linux package names and binary paths | Changing Arch-specific package names |
| `vars/debian.yml` | Debian/Ubuntu package names and binary paths | Changing Debian-specific package names |
| `vars/redhat.yml` | RedHat/Fedora package names and binary paths | Changing RedHat-specific package names |
| `vars/void.yml` | Void Linux package names and binary paths | Changing Void-specific package names |
| `vars/gentoo.yml` | Gentoo package names (`app-shells/zsh`, `app-shells/fish`) and binary paths | Changing Gentoo-specific package names |

## Examples

### Using zsh (default)

```yaml
# In group_vars/all/shell.yml or host_vars/<hostname>/shell.yml:
shell_type: zsh
shell_set_login: true
shell_zsh_zdotdir: true
```

This installs zsh, sets it as the login shell, creates XDG directories, deploys `/etc/profile.d/dev-paths.sh` with PATH additions, and sets `ZDOTDIR` in `/etc/zsh/zshenv`.

### Switching to fish

```yaml
# In host_vars/<hostname>/shell.yml:
shell_type: fish
```

Installs fish, sets it as the login shell, deploys `/etc/fish/conf.d/dev-paths.fish` instead of `/etc/profile.d/dev-paths.sh`. The fish template uses `fish_add_path` and `set -gx` instead of POSIX syntax.

### Adding custom PATH entries and environment variables

```yaml
# In group_vars/developers/shell.yml:
shell_global_path:
  - "$HOME/.local/bin"
  - "$HOME/.cargo/bin"
  - "/usr/local/go/bin"
  - "$HOME/.npm-global/bin"
shell_global_env:
  GOPATH: "$HOME/go"
  JAVA_HOME: "/usr/lib/jvm/default"
```

### Keeping bash without changing login shell

```yaml
# In host_vars/<hostname>/shell.yml:
shell_type: bash
shell_set_login: false
```

No package is installed (bash is always present). Login shell is not changed. XDG directories and `/etc/profile.d/dev-paths.sh` are still deployed.

## Cross-platform details

| Aspect | Arch Linux | Debian / Ubuntu | RedHat / Fedora | Void Linux | Gentoo |
|--------|-----------|-----------------|-----------------|------------|--------|
| zsh package | `zsh` | `zsh` | `zsh` | `zsh` | `app-shells/zsh` |
| fish package | `fish` | `fish` | `fish` | `fish` | `app-shells/fish` |
| bash binary | `/bin/bash` | `/bin/bash` | `/bin/bash` | `/bin/bash` | `/bin/bash` |
| zsh binary | `/usr/bin/zsh` | `/usr/bin/zsh` | `/usr/bin/zsh` | `/usr/bin/zsh` | `/usr/bin/zsh` |
| fish binary | `/usr/bin/fish` | `/usr/bin/fish` | `/usr/bin/fish` | `/usr/bin/fish` | `/usr/bin/fish` |

Config file paths are the same across all distros:

| Config file | Path | Deployed when |
|------------|------|---------------|
| POSIX profile | `/etc/profile.d/dev-paths.sh` | `shell_type` is `bash` or `zsh` |
| zsh environment | `/etc/zsh/zshenv` | `shell_type` is `zsh` |
| fish config | `/etc/fish/conf.d/dev-paths.fish` | `shell_type` is `fish` |

## Logs

This role does not create log files or configure log rotation. All output is visible in the Ansible run output.

### Diagnostic commands

| What to check | Command |
|---------------|---------|
| Current login shell | `getent passwd <username>` -- 7th field is the login shell |
| Shell binary version | `zsh --version` / `fish --version` / `bash --version` |
| Profile.d is sourced | `echo $PATH` after login -- should contain `.local/bin`, `.cargo/bin`, `go/bin` |
| ZDOTDIR is set (zsh) | `echo $ZDOTDIR` -- should show `~/.config/zsh` |
| XDG dirs exist | `ls -la ~/.config ~/.local/share ~/.local/bin ~/.cache` |

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Login shell not changed | `getent passwd <user>` -- check 7th field | Verify `shell_set_login: true` and `shell_type` is correct. Run role again |
| Shell binary not found | `which zsh` or `which fish` returns nothing | Package not installed. Check `ansible_facts['os_family']` matches a supported family. Run role with `-v` to see package task |
| `/etc/profile.d/dev-paths.sh` not sourced | `echo $PATH` missing expected entries after login | Verify file exists: `cat /etc/profile.d/dev-paths.sh`. Non-login shells skip `/etc/profile.d/`. Use `zsh -l` or `bash -l` for login shell |
| ZDOTDIR not set after login | `echo $ZDOTDIR` is empty | Check `/etc/zsh/zshenv` exists and contains `export ZDOTDIR`. Verify `shell_zsh_zdotdir: true`. Some distros source `/etc/zshenv` instead of `/etc/zsh/zshenv` |
| XDG directories have wrong owner | `ls -la ~/.config` shows root ownership | Check `shell_user` is set correctly. If run as root without `SUDO_USER`, dirs are created under `/root/`. Set `shell_user` explicitly in inventory |
| Fish PATH not updated | `echo $PATH` in fish missing entries | Check `/etc/fish/conf.d/dev-paths.fish` exists. Fish ignores `/etc/profile.d/` -- it needs its own config in `/etc/fish/conf.d/` |
| Role fails at Validate step | Read the `fail_msg` in output | Check `shell_type` is `bash`, `zsh`, or `fish`. Check OS family is supported. Check `shell_user` is defined |
| Gentoo package install fails | `emerge` error in output | Gentoo uses `app-shells/zsh` and `app-shells/fish`. Verify `vars/gentoo.yml` has correct atom names |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Logic correctness, idempotence, config deployment on Arch + Ubuntu containers |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic or login shell tasks | Real systemd, real packages, real non-root user (`vagrant`), Arch + Ubuntu VMs |
| Default (localhost) | `molecule test` | Quick syntax check and local validation | Syntax, converge, idempotence, verify on the local machine |

### Success criteria

- All steps complete: `syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass
- Final line: no `failed` tasks

### What the tests verify

| Category | What is checked | How |
|----------|----------------|-----|
| Package | zsh installed, binary exists and is executable | `package_facts` + `stat` on binary |
| `/etc/shells` | Shell binary is registered in `/etc/shells` | `slurp` + content check |
| Login shell | `getent passwd` shows correct shell for user | `getent` + assert |
| XDG directories | `.config`, `.local/share`, `.local/bin`, `.cache` exist with correct owner | `stat` + assert on each dir |
| `/etc/profile.d/dev-paths.sh` | Exists, mode 0644, owned by root, contains PATH entries and `export PATH`, contains Ansible managed marker | `stat` + `slurp` + content asserts |
| `/etc/zsh/zshenv` | Exists, mode 0644, owned by root, contains `export ZDOTDIR` with XDG path, contains Ansible managed marker | `stat` + `slurp` + content asserts |
| Runtime | Shell binary responds to `--version` | `command` + rc check |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `zsh package not found` | Stale package cache in container | Rebuild: `molecule destroy -s docker && molecule test -s docker` |
| Idempotence failure on config deploy | Template produces different output on second run | Check for timestamps or random values in template |
| `Assertion failed` on login shell | User's shell was not changed | Verify `shell_set_login: true` in converge.yml variables |
| XDG directory ownership mismatch | Running in Docker as root without `SUDO_USER` | Expected in Docker -- dirs are created under `/root/`. Vagrant scenario tests real non-root user |
| Vagrant: `Python not found` | prepare.yml missing or Arch bootstrap skipped | Check `prepare.yml` imports shared vagrant prepare playbook |
| `/etc/zsh/zshenv` not found | zshenv template not deployed | Check `shell_type` is `zsh` in converge.yml. Check `/etc/zsh/` directory was created |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `shell` | Entire role (validate, install, chsh, xdg, global config, verify, report) | Full apply: `ansible-playbook playbook.yml --tags shell` |
| `shell,report` | Report rendering only | Re-generate execution report: `ansible-playbook playbook.yml --tags shell,report` |
| `shell,install` | Package installation only | Reinstall shell package: `ansible-playbook playbook.yml --tags "shell,install"` |
| `shell,configure` | Login shell, XDG dirs, and global config tasks | Re-apply configuration without reinstalling: `ansible-playbook playbook.yml --tags "shell,configure"` |

Use `--skip-tags report` in molecule and automation pipelines to suppress the execution report.

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with comments | No -- override via inventory |
| `vars/main.yml` | Supported OS families and shell types lists | Only when adding new OS or shell support |
| `vars/<os_family>.yml` | Per-distro package names and binary paths | Only when changing distro-specific packages |
| `tasks/main.yml` | Execution flow orchestrator: resolve user, load vars, include task files | When adding/removing execution steps |
| `tasks/validate.yml` | Preflight assertions (OS, shell_type, shell_user) | When adding new validation checks |
| `tasks/install.yml` | Package installation via `ansible.builtin.package` | Rarely |
| `tasks/chsh.yml` | Login shell change via `ansible.builtin.user` | Rarely |
| `tasks/xdg.yml` | XDG Base Directory creation | When changing directory list or permissions |
| `tasks/global.yml` | Template deployment for profile.d, zshenv, fish conf.d | When adding new config files |
| `tasks/verify.yml` | In-role verification (login shell, XDG dirs, config files) | When adding new verification checks |
| `templates/profile.d-dev-paths.sh.j2` | POSIX shell PATH and env var template | When changing PATH/env syntax |
| `templates/zshenv.j2` | zsh ZDOTDIR template | When changing ZDOTDIR logic |
| `templates/fish-dev-paths.fish.j2` | Fish shell PATH and env var template | When changing fish-specific syntax |
| `handlers/main.yml` | Empty -- present for role structure completeness | No |
| `meta/main.yml` | Galaxy metadata, platform list, dependencies | When updating metadata |
| `molecule/` | Test scenarios (default, docker, vagrant) | When changing test coverage |
