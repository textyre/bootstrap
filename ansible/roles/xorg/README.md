# xorg

X11 (Xorg) configuration — deploys system config files to `/etc/X11/xorg.conf.d/`.

## What this role does

- [x] Creates `/etc/X11/xorg.conf.d/` directory (root:root 0755)
- [x] Deploys `00-keyboard.conf` — keyboard layout (US + RU, toggle with `Ctrl+Space`)
- [x] Deploys `10-monitor.conf` — monitor/device/screen configuration with modesetting driver
- [x] Validates that the dotfiles source directory exists before copying
- [x] Configuration-only role — no display server required, no packages installed

## Requirements

- Source dotfiles must be present on the target host. The role reads files from
  `xorg_source_dir` (defaults to `dotfiles/` in the repo root via `REPO_ROOT` env var
  or `dotfiles_base_dir` variable).
- The role uses `ansible.builtin.copy` with `remote_src: true`, so the dotfiles directory
  must be synced to the managed host before running the role (handled by the `chezmoi` or
  deployment playbook).

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `xorg_source_dir` | `{{ dotfiles_base_dir \| default(lookup('env', 'REPO_ROOT') ~ '/dotfiles', true) }}` | Absolute path to the dotfiles source directory on the managed host |
| `xorg_system_files` | See below | List of config file descriptors (`src`, `dest`, `owner`, `group`, `mode`) |

### Default `xorg_system_files`

```yaml
xorg_system_files:
  - src: "etc/X11/xorg.conf.d/00-keyboard.conf"
    dest: "/etc/X11/xorg.conf.d/00-keyboard.conf"
    owner: root
    group: root
    mode: "0644"
  - src: "etc/X11/xorg.conf.d/10-monitor.conf"
    dest: "/etc/X11/xorg.conf.d/10-monitor.conf"
    owner: root
    group: root
    mode: "0644"
```

## Dependencies

None. `dependencies: []`

## Tags

| Tag | Runs |
|-----|------|
| `xorg` | All tasks |
| `display` | All tasks |

## Example Playbook

```yaml
- name: Configure Xorg
  hosts: workstations
  become: true
  roles:
    - role: xorg
      vars:
        xorg_source_dir: "{{ ansible_env.HOME }}/bootstrap/dotfiles"
```

## Supported Platforms

| Platform | Versions |
|----------|---------|
| Arch Linux | all |
| Ubuntu | all |

## Testing

Tests live in `molecule/`. The role has two scenarios sharing a single converge/verify playbook via `molecule/shared/`.

### Scenarios

| Scenario | Driver | Purpose |
|----------|--------|---------|
| `default` | `default` (localhost, `ansible_connection: local`) | Fast local smoke test — no containers needed |
| `docker` | `docker` | Full isolated test in an Arch Linux systemd container |

### Running tests

```bash
# Activate venv
source ansible/.venv/bin/activate

# Default scenario (localhost, fast)
cd ansible/roles/xorg
molecule test

# Docker scenario (isolated container)
molecule test -s docker
```

The `default` scenario runs: `syntax → converge → idempotence → verify`.

The `docker` scenario runs: `syntax → create → prepare → converge → idempotence → verify → destroy`.

> **Note:** No display server (`Xorg`, `Wayland`) is required for testing. The role only
> deploys config files; correctness is verified by asserting file existence, permissions,
> and content — all testable in a headless container.

### What the verifier checks

- `/etc/X11/xorg.conf.d/` directory exists with `root:root 0755`
- `00-keyboard.conf` exists with `root:root 0644`, contains `XkbLayout` and `us`
- `10-monitor.conf` exists with `root:root 0644`, contains `Monitor` section

## Known Issues / Bug Fixes

### `xorg_source_stat` variable name bug (fixed)

In an earlier version the `stat` task registered its result as `source_stat` instead of
`xorg_source_stat`, causing the subsequent `assert` task to always pass vacuously (it
referenced an undefined variable). The fix was to align the `register:` name with the
`xorg_` prefix used everywhere else in the role.
