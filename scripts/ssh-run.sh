#!/usr/bin/env bash
# ssh-run.sh - Execute commands on VM via SSH
#
# Usage:
#   ./scripts/ssh-run.sh <command>
#   ./scripts/ssh-run.sh "ls -la"
#   ./scripts/ssh-run.sh "df -h && free -m"
#
# Environment variables:
#   SSH_HOST - override default host (default: arch-127.0.0.1-2222)

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command>" >&2
    echo "Example: $0 'ls -la'" >&2
    exit 1
fi

COMMAND="$*"

ssh $SSH_OPTS "$SSH_HOST" "$COMMAND"
