---
name: dotfiles
description: Deploy dotfile changes using chezmoi. Handles syncing templates to remote VM and applying configurations with service restarts.
metadata:
  argument-hint: <file-path>
  allowed-tools: Bash(bash scripts/ssh-scp-to.sh *), Bash(bash scripts/ssh-run.sh *)
---

# Dotfiles Deployment (chezmoi)

Deploy dotfile configuration changes to the remote VM using chezmoi.

## Important: How chezmoi works on remote

`chezmoi apply` on the remote VM reads from its own local source at `/home/textyre/.local/share/chezmoi/`, NOT from the Windows host.

After editing templates locally, you MUST sync them to the remote before applying.

## Deployment workflow

### 1. Copy changed files to remote chezmoi source

```bash
bash scripts/ssh-scp-to.sh dotfiles/<path> /home/textyre/.local/share/chezmoi/<path>
```

**IMPORTANT:** Strip the `dotfiles/` prefix when constructing the remote path. The remote chezmoi source should never contain a `dotfiles/` subdirectory.

**Examples:**
- Local: `dotfiles/ewwii/config.yuck` → Remote: `/home/textyre/.local/share/chezmoi/ewwii/config.yuck`
- Local: `dotfiles/waybar/config.jsonc` → Remote: `/home/textyre/.local/share/chezmoi/waybar/config.jsonc`

### 2. Apply and restart affected services

For **ewwii** configuration changes:
```bash
bash scripts/ssh-run.sh "chezmoi apply && pkill ewwii; sleep 1; nohup ~/.config/ewwii/launch.sh > /dev/null 2>&1 & disown"
```

For **waybar** configuration changes:
```bash
bash scripts/ssh-run.sh "chezmoi apply && pkill waybar; sleep 1; nohup waybar > /dev/null 2>&1 & disown"
```

For **general** configuration changes (no service restart):
```bash
bash scripts/ssh-run.sh "chezmoi apply"
```

## Common scenarios

### Editing existing template
1. Edit file locally in `dotfiles/` directory
2. Use this skill with the file path: `/dotfiles <path>`
3. Skill will sync and apply

### Renaming a file (e.g., `.conf` to `.conf.tmpl`)
1. Delete the old file from remote chezmoi source first:
   ```bash
   bash scripts/ssh-run.sh "rm /home/textyre/.local/share/chezmoi/<old-path>"
   ```
2. Copy new file with new name
3. Apply chezmoi

### Multiple files changed
Copy each file separately, then apply once:
```bash
bash scripts/ssh-scp-to.sh dotfiles/file1 /home/textyre/.local/share/chezmoi/file1
bash scripts/ssh-scp-to.sh dotfiles/file2 /home/textyre/.local/share/chezmoi/file2
bash scripts/ssh-run.sh "chezmoi apply"
```

## What to do with the argument

If the user provides a file path (e.g., `/dotfiles ewwii/config.yuck`):

1. **Sync the file:**
   ```bash
   bash scripts/ssh-scp-to.sh dotfiles/$ARGUMENT /home/textyre/.local/share/chezmoi/$ARGUMENT
   ```

2. **Determine which service to restart** based on the path:
   - `ewwii/` → restart ewwii
   - `waybar/` → restart waybar
   - Other → just apply, no restart

3. **Apply and restart:**
   ```bash
   bash scripts/ssh-run.sh "chezmoi apply && pkill SERVICE; sleep 1; nohup SERVICE-launch-command > /dev/null 2>&1 & disown"
   ```

If no argument provided, ask the user which file(s) they want to deploy.

## Verification

After deployment, verify the changes:
```bash
bash scripts/ssh-run.sh "cat ~/.config/<service>/<config-file>"
```

Or check if the service is running:
```bash
bash scripts/ssh-run.sh "pgrep -a ewwii"  # or waybar, etc
```

## Troubleshooting

### File not found on remote
- Check if the file exists locally in `dotfiles/` directory
- Verify the path mapping (strip `dotfiles/` prefix)

### chezmoi apply fails
- Check chezmoi source is intact: `bash scripts/ssh-run.sh "ls -la ~/.local/share/chezmoi/"`
- Verify template syntax: `bash scripts/ssh-run.sh "chezmoi execute-template < ~/.local/share/chezmoi/<file>"`

### Service won't restart
- Check if service is installed: `bash scripts/ssh-run.sh "which ewwii"`
- Try manual restart: `bash scripts/ssh-run.sh "~/.config/ewwii/launch.sh"`
- Check logs: use `/remote` skill to check system logs
