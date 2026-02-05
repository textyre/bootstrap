# Chezmoi Integration Guide

## Overview

This project uses [chezmoi](https://www.chezmoi.io/) to manage dotfiles across Arch Linux servers.

## Structure

- **`dotfiles/`** - chezmoi repository with all managed dotfiles
  - `dot_xinitrc` → deployed as `~/.xinitrc`
  - `dot_config/i3/config` → deployed as `~/.config/i3/config`
  - `.chezmoi.toml.tmpl` - chezmoi configuration template

## Bootstrap Integration

During `./bootstrap/bootstrap.sh`:

1. **Package installation** - `chezmoi` package is installed via pacman
2. **Dotfiles application** - Ansible chezmoi role runs:
   ```bash
   chezmoi init --apply /path/to/dotfiles
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

1. Place source file in `dotfiles/` with `dot_` prefix:
   - `~/.bashrc` → `dotfiles/dot_bashrc`
   - `~/.config/foo/bar` → `dotfiles/dot_config/foo/bar`

2. Commit to git

3. Run `chezmoi apply` on target system

## File Naming Convention

- Files starting with `.` → use `dot_` prefix in chezmoi
  - `~/.xinitrc` = `dot_xinitrc`
  - `~/.config/` = `dot_config/`

- Regular files keep normal names
  - `~/scripts/foo` = `scripts/foo`

## Template Variables

Chezmoi templates используют переменные из `.chezmoidata/`:

```go
{{ $t := index .themes .theme_name }}     // Current theme
{{ $t.bg }}                               // Background color
{{ $t.fg }}                               // Foreground color
{{ $t.accent }}                           // Primary accent

{{ .layout.gaps_outer }}                  // 8
{{ .layout.bar_height }}                  // 32
{{ .font.mono }}                          // JetBrainsMono Nerd Font
```

## Configuration Files

### `.chezmoidata/themes.toml`
```toml
[themes.dracula]
bg = "#11111b"
fg = "#cdd6f4"
accent = "#cba6f7"
# ... more colors

[themes.monochrome]
bg = "#0a0a0a"
fg = "#c0c0c0"
# ... grayscale theme
```

### `.chezmoidata/layout.toml`
```toml
[layout]
gaps_inner = 4
gaps_outer = 8
bar_height = 32
bar_radius = 14
# ... more layout parameters
```

### `.chezmoidata/fonts.toml`
```toml
[font]
mono = "JetBrainsMono Nerd Font Mono"
bar_size = 10
icon_size = 16
```

## Theme Switching

When switching themes:

```bash
# Update chezmoi.toml
# theme_name = "monochrome"

# Re-apply all templates
chezmoi apply

# Reload services (polybar, i3, etc.)
~/.config/polybar/launch.sh
i3-msg reload
```

## References

- [chezmoi Documentation](https://www.chezmoi.io/)
- [chezmoi Quick Start](https://www.chezmoi.io/quick-start/)

---

Назад к [[Home]]
