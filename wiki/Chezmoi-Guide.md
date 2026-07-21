# Chezmoi Integration Guide

## Purpose

Chezmoi is the single engine that renders and applies user dotfiles from the
repository's `dotfiles/` source tree. The Ansible `chezmoi` role runs it for the
project-wide `target_user` after the `user` role has provided the account.

## Bootstrap pipeline

1. `packages` installs the system-wide chezmoi executable.
2. `user` ensures `target_user` exists before the role runs.
3. The role initializes the user's config from
   `dotfiles/.chezmoi.toml.tmpl` when needed.
4. The role enforces `chezmoi_theme_name` in that config.
5. `chezmoi apply` renders templates and brings the user's managed files to the
   source state.

The role does not copy individual dotfiles or calculate file checksums.
Repository wallpapers are intentionally ignored by chezmoi and synchronized by
the role to `~/.local/share/wallpapers/`.

## Source structure

| Path | Purpose |
|------|---------|
| `dotfiles/.chezmoi.toml.tmpl` | Generates the user's chezmoi config and theme data. |
| `dotfiles/.chezmoidata/*.toml` | Shared values for themes, fonts, layout, terminal, lock screen, and desktop tools. |
| `dotfiles/dot_config/` | Files rendered below `~/.config/`. |
| `dotfiles/dot_local/` | Files rendered below `~/.local/`, including executable helpers. |
| `dotfiles/wallpapers/` | Images copied by the role to `~/.local/share/wallpapers/`. |
| `dotfiles/dot_xinitrc` | X11 startup file rendered as `~/.xinitrc`. |
| `dotfiles/.chezmoiscripts/` | Source-controlled scripts; layout constants use `run_onchange_after` and run only when their rendered input changes. |
| `dotfiles/.chezmoiignore` | Source entries intentionally excluded from the target home. |

Chezmoi naming maps `dot_` to a leading dot and `executable_` to executable
mode. For example, `dot_config/i3/config.tmpl` becomes `~/.config/i3/config`,
and `dot_local/bin/executable_theme-switch` becomes
`~/.local/bin/theme-switch`.

## Theme data

`chezmoi_theme_name` currently accepts the choices declared by
`.chezmoi.toml.tmpl`: `dracula` and `monochrome`. Templates select the matching
entry from `.chezmoidata/themes.toml` and combine it with component data such as
`layout.toml`, `fonts.toml`, `rofi.toml`, and `terminal.toml`.

Set the desired theme in inventory and rerun the role:

```yaml
chezmoi_theme_name: monochrome
```

## Component-specific layout values

Values with similar names are not automatically interchangeable. The current
source uses `dunst.corner_radius = 8` for notifications and
`layout.corner_radius = 10` for Picom, GTK, and Rofi. Keep this difference
visible when changing the visual system; do not silently replace one with the
other. If a single radius becomes the desired design, update the data ownership
and every consuming template together.

## Manual inspection

Run these as the target user on a prepared host:

```bash
chezmoi status
chezmoi diff
chezmoi data
```

The next normal Ansible run applies pending source changes. Direct manual edits
to generated target files are not the source of truth and can be replaced by
the next apply.

## Adding managed files

1. Add the source file under `dotfiles/` using chezmoi attributes.
2. Add reusable values to the appropriate `.chezmoidata/*.toml` file when the
   content is templated.
3. Run the role through the project test workflow and confirm idempotence.
4. Commit the source change together with any affected documentation.

## References

- [Chezmoi documentation](https://www.chezmoi.io/)
- [Chezmoi command overview](https://www.chezmoi.io/user-guide/command-overview/)

Назад к [[Home]]
