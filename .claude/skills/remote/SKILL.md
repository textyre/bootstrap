---
name: remote
description: Execute commands on the remote Arch Linux VM via SSH. Use for any operation that must run on the VM — checking services, logs, file state, package queries, process management.
metadata:
  argument-hint: <command>
  allowed-tools: Bash(bash scripts/ssh-run.sh *), Bash(bash scripts/ssh-scp-to.sh *), Bash(bash scripts/ssh-sudo.sh *), Bash(bash scripts/ssh-scp-from.sh *)
---

# Remote VM Execution

Execute commands on the remote Arch Linux VM (VirtualBox, NAT 127.0.0.1:2222, user: textyre).

## Connection details

- SSH host alias: `arch-127.0.0.1-2222`
- User: `textyre`
- Home: `/home/textyre`
- Chezmoi source: `/home/textyre/.local/share/chezmoi/`
- Ansible project: `/home/textyre/bootstrap/`
- Run script: `bash scripts/ssh-run.sh "<command>"`
- Copy script: `bash scripts/ssh-scp-to.sh <local-path> <remote-path>`

## What to do

Run the following command on the remote VM:

```
bash scripts/ssh-run.sh "$ARGUMENTS"
```

If the command requires sudo, note that SSH uses BatchMode (no interactive password). Use Ansible for privileged operations instead.

If the command needs a graphical display, prefix with `DISPLAY=:0`.

## Copy files to remote

To copy files, use:
```
bash scripts/ssh-scp-to.sh <local-path> <remote-path>
bash scripts/ssh-scp-to.sh -r <local-dir> <remote-dir>
```

## Chezmoi deploy workflow

When deploying dotfile changes:
1. Copy to chezmoi source: `bash scripts/ssh-scp-to.sh dotfiles/<path> /home/textyre/.local/share/chezmoi/<path>`
2. Apply: `bash scripts/ssh-run.sh "chezmoi apply"`

IMPORTANT: Strip the `dotfiles/` prefix when constructing the remote path. The remote chezmoi source should never contain a `dotfiles/` subdirectory.

## Privileged operations (sudo)

SSH uses `BatchMode=yes` — interactive `sudo` via `ssh-run.sh` will ALWAYS fail with "a terminal is required". Use one of:

1. **`ssh-sudo.sh`** (simplest): `bash scripts/ssh-sudo.sh "<command>"` — reads password from `~/.vault-pass` on VM, pipes to `sudo -S`
2. **Ansible ad-hoc**: `bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible && source .venv/bin/activate && ansible localhost -m <module> -a '<args>' --become"`
3. **Ansible role** via `/ansible role <name>` skill (for multi-step operations)

NEVER use bare `sudo` in `ssh-run.sh` — it requires a terminal. Use `ssh-sudo.sh` instead.

## All available scripts

| Script | Purpose |
|--------|---------|
| `scripts/ssh-run.sh "<cmd>"` | Run command as user (no sudo) |
| `scripts/ssh-sudo.sh "<cmd>"` | Run command as root (reads password from ~/.vault-pass) |
| `scripts/ssh-scp-to.sh [-r] <local> <remote>` | Copy files TO remote |
| `scripts/ssh-scp-from.sh [-r] <remote> <local>` | Copy files FROM remote |

## File permissions after docker cp

`docker cp` copies files with container-internal permissions (often `0600` root-only). If a file must be readable by non-root users (e.g. CA certificates, config files), ALWAYS chmod after copy:
```
docker cp container:/path /host/path && chmod 644 /host/path
```

## Cleanup after subagent operations

After using remote-executor or other subagents that create temporary files on the VM, always clean up:
- Temp playbooks: `rm -f /tmp/run_role*.yml`
- Temp files in bootstrap dir: check for unexpected files in `ansible/playbooks/`