# chezmoi

Deploys user dotfiles via [chezmoi](https://www.chezmoi.io/): installs the binary, initializes chezmoi from a local source directory, and applies all managed dotfiles to the target user's home.

## What this role does

- [x] Resolves the target user's home directory via `getent`
- [x] Installs `chezmoi` via OS package manager (`pacman`, `apt`) or official install script
- [x] Asserts the dotfiles source directory exists before proceeding
- [x] Copies wallpapers from the source dir to `~/.local/share/wallpapers/` (if present)
- [x] Runs `chezmoi init --source <dir> --apply` with an optional theme prompt choice
- [x] Guards against stale nested `.chezmoidata` directories
- [x] Reports deployment summary

## Requirements

- Ansible 2.15+
- Target host: Arch Linux or Debian/Ubuntu
- The dotfiles source directory must be accessible on the **remote** host (sync it before running the role, or set `chezmoi_source_dir` to a pre-existing path)
- `curl` available on host when `chezmoi_install_method: script`

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `chezmoi_user` | current sudo user or `ansible_user_id` | Target user whose dotfiles are deployed |
| `chezmoi_source_dir` | `$REPO_ROOT/dotfiles` (or `dotfiles_base_dir`) | Path to the chezmoi source directory on the **remote** host |
| `chezmoi_install_method` | `pacman` | Installation method: `pacman`, `apt` (via OS-specific tasks), or `script` (official install script → `~/.local/bin/chezmoi`) |
| `chezmoi_theme_name` | `dracula` | Theme passed to chezmoi via `--promptChoice "Choose color theme=<value>"` |

### Derived / verify-only variables

These are not in `defaults/main.yml` but can be set in molecule inventory to control verify behaviour:

| Variable | Default | Description |
|----------|---------|-------------|
| `chezmoi_verify_has_dotfiles` | `false` | Assert `~/.local/share/chezmoi` was initialized |
| `chezmoi_verify_fixture` | `false` | Assert `~/.chezmoi_test_marker` exists (fixture/stub dotfiles scenarios) |
| `chezmoi_verify_full` | `false` | Run full dotfile checks (Arch + real dotfiles source) |

## Dependencies

None.

## Example Playbook

```yaml
- hosts: workstations
  roles:
    - role: chezmoi
      vars:
        chezmoi_user: alice
        chezmoi_source_dir: /home/alice/bootstrap/dotfiles
        chezmoi_theme_name: dracula
```

### With the workstation playbook

The role is driven by `chezmoi_source_dir`. The bootstrap repository syncs dotfiles to the remote host before invoking the role:

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

## Tags

| Tag | Effect |
|-----|--------|
| `chezmoi` | All tasks |
| `dotfiles` | All tasks (alias) |
| `install` | Installation tasks only |

## Testing

Tests use [Molecule](https://molecule.readthedocs.io/).

### Scenarios

| Scenario | Driver | Platforms | Notes |
|----------|--------|-----------|-------|
| `default` | none (localhost) | localhost (connection: local) | Fast smoke test against real dotfiles; requires `REPO_ROOT` set |
| `docker` | Docker | `arch-systemd` container | Uses fixture dotfiles under `/opt/dotfiles`; validates binary install + apply |
| `vagrant` | Vagrant + libvirt | `arch-vm`, `ubuntu-noble` | Full VM test; covers both `pacman` and `script` install methods |

### Running

```bash
# From the role directory
cd ansible/roles/chezmoi

# Default scenario (localhost, real dotfiles)
molecule test -s default

# Docker scenario
molecule test -s docker

# Vagrant scenario (requires libvirt + Vagrant)
molecule test -s vagrant

# Run only converge (no destroy)
molecule converge -s docker

# Run only verify
molecule verify -s docker
```

### What the verify checks

1. **Tier 1 — binary**: `chezmoi` is on `PATH` or at `~/.local/bin/chezmoi`; `chezmoi --version` exits 0
2. **Tier 1 — source dir**: `~/.local/share/chezmoi` exists and is a directory (when `chezmoi_verify_has_dotfiles`)
3. **Tier 1 — fixture marker**: `~/.chezmoi_test_marker` deployed by stub dotfiles (when `chezmoi_verify_fixture`)
4. **Tier 2 — dotfiles**: selected real dotfile paths exist in `$HOME` (when `chezmoi_verify_full`)
