# Chezmoi Integration Guide

## Overview

This project uses [chezmoi](https://www.chezmoi.io/) to manage dotfiles across Arch Linux servers.

## Structure

- **`scripts/dotfiles/`** - chezmoi repository with all managed dotfiles
  - `dot_xinitrc` → deployed as `~/.xinitrc`
  - `dot_config/i3/config` → deployed as `~/.config/i3/config`
  - `.chezmoi.toml.tmpl` - chezmoi configuration template

## Bootstrap Integration

During `./bootstrap/bootstrap.sh`:

1. **Package installation** - `chezmoi` package is installed via pacman
2. **Dotfiles application** - `scripts/bootstrap/gui/deploy-dotfiles.sh` runs:
   ```bash
   chezmoi init --apply /path/to/scripts/dotfiles
   ```

## Manual Dotfiles Operations

### Initialize chezmoi
```bash
chezmoi init https://github.com/user/scripts --apply
```

### Update dotfiles
```bash
chezmoi pull --apply
```

### Preview changes
```bash
chezmoi diff
```

### Edit a dotfile
```bash
chezmoi edit ~/.xinitrc
```

## Adding New Dotfiles

1. Place source file in `scripts/dotfiles/` with `dot_` prefix:
   - `~/.bashrc` → `scripts/dotfiles/dot_bashrc`
   - `~/.config/foo/bar` → `scripts/dotfiles/dot_config/foo/bar`

2. Commit to git

3. Run `chezmoi apply` on target system

## File Naming Convention

- Files starting with `.` → use `dot_` prefix in chezmoi
  - `~/.xinitrc` = `dot_xinitrc`
  - `~/.config/` = `dot_config/`

- Regular files keep normal names
  - `~/scripts/foo` = `scripts/foo`

## References

- [chezmoi Documentation](https://www.chezmoi.io/)
- [chezmoi Quick Start](https://www.chezmoi.io/quick-start/)
