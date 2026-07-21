# Dotfiles

This directory is the chezmoi source used by the Ansible `chezmoi` role.

Key paths:

- `.chezmoi.toml.tmpl` generates the target user's chezmoi configuration.
- `.chezmoidata/` contains reusable template data.
- `dot_config/` maps to `~/.config/`.
- `dot_local/` maps to `~/.local/`, including executable helpers.
- `wallpapers/` is ignored by chezmoi and copied by the role to the user's XDG data directory.
- `.chezmoiscripts/` contains source-controlled post-apply scripts.
- `.chezmoiignore` excludes repository-only content.

The role applies this source from the project-wide `dotfiles_base_dir`; user
creation belongs to an earlier workstation stage.

For manual read-only inspection as the target user:

```bash
chezmoi status
chezmoi diff
chezmoi data
```
