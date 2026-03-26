# chezmoi

Deploys user dotfiles via [chezmoi](https://www.chezmoi.io/): installs the binary, initialises from a local source directory, and applies all managed dotfiles to the target user's home.

## Execution flow

1. **Preflight** — asserts `ansible_facts['os_family']` is one of the five supported families; fails fast with a clear message if not.
2. **Resolve paths** — resolves the target user's home directory via `getent passwd`.
3. **Install** (`tasks/install-<os_family>.yml`) — installs chezmoi via OS package manager (`pacman` on Arch) or official install script (`~/.local/bin/chezmoi`). Skipped silently if the binary already exists (`creates:` guard on the script).
4. **Resolve binary path** — sets `_chezmoi_bin` to `/usr/bin/chezmoi` (pacman) or `~/.local/bin/chezmoi` (script).
5. **Validate source** — asserts `chezmoi_source_dir` exists and is a directory on the remote host. Fails with path in error if missing.
6. **Wallpapers** — if `chezmoi_source_dir/wallpapers/` exists, deploys wallpapers to `~/.local/share/wallpapers/`.
7. **Initialize chezmoi** (first run only) — runs `chezmoi init --source <dir> --promptChoice "..." --apply`. Skipped if `~/.config/chezmoi/chezmoi.toml` already exists. Always reports `changed`.
8. **Apply chezmoi** (subsequent runs) — runs `chezmoi apply --source <dir>`. Reports `changed` only if chezmoi modifies files; `ok` when nothing changes (idempotent).
9. **Nested chezmoidata guard** — runs `find` to detect stale `.chezmoidata` dirs nested inside the source; fails if any found.
10. **Verify** (`tasks/verify.yml`) — checks binary responds to `--version`, asserts version format, checks source dir is still accessible, asserts `chezmoi.toml` config was deployed.
11. **Report** — writes execution report via `common/report_phase` + `common/report_render`.

### Handlers

None. chezmoi does not manage system services.

## Variables

### Configurable (`defaults/main.yml`)

Override via inventory (`group_vars/` or `host_vars/`). Never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `chezmoi_enabled` | `true` | safe | Set `false` to skip the role entirely |
| `chezmoi_user` | `$SUDO_USER` or `ansible_user_id` | safe | Target user whose dotfiles are deployed |
| `chezmoi_source_dir` | `$REPO_ROOT/dotfiles` | careful | Path to chezmoi source directory **on the remote host**. Must exist before the role runs. |
| `chezmoi_install_method` | `pacman` | careful | `pacman` (Arch only) or `script` (official install script → `~/.local/bin/chezmoi`). Wrong method for the OS silently skips install. |
| `chezmoi_theme_name` | `dracula` | safe | Theme name passed via `--promptChoice "Choose color theme=<value>"` on first init only. No effect on subsequent runs (config already exists). |

### Internal mappings (`vars/`)

Do not override via inventory. Edit only when adding distro support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | `_chezmoi_packages`: OS-family → package name (Arch=`chezmoi`, others=N/A). chezmoi has no service mapping. | Adding a new distro that ships chezmoi as a package |

## Examples

### Deploying dotfiles for a specific user

```yaml
# In host_vars/<hostname>/chezmoi.yml:
chezmoi_user: alice
chezmoi_source_dir: /opt/bootstrap/dotfiles
chezmoi_theme_name: nord
```

### Skipping the role on a specific host

```yaml
# In host_vars/<hostname>/chezmoi.yml:
chezmoi_enabled: false
```

### Using script install on Ubuntu

```yaml
# In host_vars/ubuntu-workstation/chezmoi.yml:
chezmoi_install_method: script
chezmoi_user: bob
chezmoi_source_dir: /opt/dotfiles
```

### With the workstation playbook (sync dotfiles first)

```yaml
- hosts: workstation
  pre_tasks:
    - name: Sync dotfiles to remote
      ansible.posix.synchronize:
        src: "{{ playbook_dir }}/../../dotfiles/"
        dest: /opt/dotfiles/
  roles:
    - role: chezmoi
      vars:
        chezmoi_source_dir: /opt/dotfiles
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RedHat | Void Linux | Gentoo |
|--------|-----------|-----------------|-----------------|------------|--------|
| Package available | yes (`pacman`) | no | no | no | no |
| Default install method | `pacman` | `script` | `script` | `script` | `script` |
| Binary path (pacman) | `/usr/bin/chezmoi` | — | — | — | — |
| Binary path (script) | `~/.local/bin/chezmoi` | `~/.local/bin/chezmoi` | `~/.local/bin/chezmoi` | `~/.local/bin/chezmoi` | `~/.local/bin/chezmoi` |
| `curl` required | only if method=script | yes | yes | yes | yes |

chezmoi has no system service and does not interact with init systems.

## Logs

### Ansible execution report

The role emits a structured execution report at the end of each run via `common/report_render.yml`, visible in Ansible stdout. Phases reported: Install chezmoi, Apply dotfiles, Verify.

To replay just the report without re-running the role:

```bash
ansible-playbook workstation.yml --tags report
```

### chezmoi runtime output

chezmoi does not write persistent log files. All output goes to stdout during the `chezmoi apply` run, captured in the Ansible task output. To inspect state on the target host:

```bash
# As the target user:
chezmoi status           # pending changes
chezmoi diff             # diff of pending changes
chezmoi doctor           # self-diagnostic
```

### Files written by this role

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| chezmoi config | `~/.config/chezmoi/chezmoi.toml` | Source dir, theme setting | Manual — do not delete unless re-initialising |
| Wallpapers | `~/.local/share/wallpapers/` | Copied from source if present | None — static files |

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in supported list | Check `ansible_facts['os_family']` on the host; only Archlinux/Debian/RedHat/Void/Gentoo are supported |
| Role fails at "Assert chezmoi source directory exists" | `chezmoi_source_dir` does not exist on the remote | Sync dotfiles before the role runs; verify path with `stat {{ chezmoi_source_dir }}` on the remote |
| chezmoi binary missing after script install | `curl` not installed, or home dir path incorrect | Ensure `curl` is in `prepare.yml`; check `chezmoi_user_home` resolves via `getent passwd <user>` |
| `chezmoi apply` reports `changed` every run | `chezmoi.toml` missing so init runs every time | Check `~/.config/chezmoi/chezmoi.toml` exists; if corrupt, delete and re-run to force clean re-init |
| "Nested chezmoidata" task fails | Stale `.chezmoidata` dir nested inside source tree | Remove nested `.chezmoidata` dirs; root-level `chezmoi_source_dir/.chezmoidata` is expected |
| Theme not applied after change | `--promptChoice` runs only on first init | Delete `~/.config/chezmoi/chezmoi.toml` and re-run to force re-init with new theme |

## Testing

Both scenarios are required (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test` | After changing variables or task logic | Idempotence, pacman + script install, fixture marker deploy |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic | Real packages, Arch + Ubuntu matrix, real home directories |

### Success criteria

- All steps complete: `syntax → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run — `chezmoi apply` has no pending changes)
- Verify step: all assertions pass with `success_msg`
- Final line: no `failed` tasks

### What the tests verify

| Category | What is checked | Requirement |
|----------|----------------|-------------|
| Binary | chezmoi at expected path; `--version` exits 0 | TEST-008 |
| Version format | stdout matches `^chezmoi version v[0-9]+\.[0-9]+` | TEST-008 |
| Config | `~/.config/chezmoi/chezmoi.toml` exists after apply | TEST-008 |
| Fixture marker | `~/.chezmoi_test_marker` deployed with correct content | TEST-008 |
| Source dir | `chezmoi_source_dir` accessible after apply | TEST-008 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `chezmoi package not found` on Arch | Stale pacman cache | `molecule destroy && molecule test` to rebuild container |
| Idempotence failure: `changed=1` | Fixture dotfiles have differences chezmoi always re-applies | Check source fixture has stable content; verify `.chezmoi.toml.tmpl` is static |
| `Assert chezmoi version output` fails | Binary not at expected path | Verify `chezmoi_install_method` matches the OS in molecule host_vars |
| `Assert fixture marker` fails | prepare.yml did not create fixture files | Run `molecule prepare -s docker` and verify `/opt/dotfiles/dot_chezmoi_test_marker` exists |
| Vagrant: Python interpreter not found | prepare.yml missing Python bootstrap step | Add `ansible.builtin.raw: pacman -Sy --noconfirm python` for Arch prepare step |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `chezmoi` | Entire role | Full apply |
| `dotfiles` | Entire role (alias) | Same as `chezmoi` |
| `install` | Install tasks only | Re-install binary without re-applying dotfiles |
| `report` | Logging/report tasks only | Re-generate execution report |

Command example:

```bash
ansible-playbook workstation.yml --tags install
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings | No — override via inventory |
| `vars/main.yml` | OS-family package name mappings | Only when adding a distro that ships chezmoi as a package |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing phases |
| `tasks/verify.yml` | Post-deploy self-check | When changing verification logic |
| `tasks/install-archlinux.yml` | Arch-specific install (pacman) | When changing Arch install method |
| `tasks/install-debian.yml` | Debian/Ubuntu install (script) | When changing Debian install method |
| `meta/main.yml` | Role metadata and supported platforms | Only when adding distro support |
| `molecule/docker/` | Docker test scenario (Arch + Ubuntu containers) | When changing test coverage |
| `molecule/vagrant/` | Vagrant test scenario (Arch + Ubuntu VMs) | When changing full-VM test coverage |
| `molecule/shared/` | Shared converge + verify playbooks | When changing test logic shared by both scenarios |
