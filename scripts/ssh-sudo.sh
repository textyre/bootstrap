#!/usr/bin/env bash
# ssh-sudo.sh - Execute sudo commands on VM using password from vault
#
# Usage:
#   ./scripts/ssh-sudo.sh <command>
#   ./scripts/ssh-sudo.sh "systemctl restart sshd"
#   ./scripts/ssh-sudo.sh "pacman -Syu --noconfirm"
#
# The script:
# 1. Retrieves sudo password from ~/.vault-pass on the VM
# 2. Executes the command with sudo -S (password via stdin)

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command>" >&2
    echo "Example: $0 'systemctl restart sshd'" >&2
    exit 1
fi

COMMAND="$*"

# Get password and execute command in one SSH session to avoid race conditions
ssh $SSH_OPTS "$SSH_HOST" "
    SUDO_PASS=\$(cat ~/.vault-pass)
    echo \"\$SUDO_PASS\" | sudo -S $COMMAND
"
