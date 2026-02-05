#!/usr/bin/env bash
# ssh-scp-to.sh - Copy files TO the VM
#
# Usage:
#   ./scripts/ssh-scp-to.sh <local-path> <remote-path>
#   ./scripts/ssh-scp-to.sh ./file.txt /home/user/
#   ./scripts/ssh-scp-to.sh -r ./dir/ /home/user/dir/

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 [-r] <local-path> <remote-path>" >&2
    echo "  -r  Copy directories recursively" >&2
    exit 1
fi

RECURSIVE=""
if [[ "$1" == "-r" ]]; then
    RECURSIVE="-r"
    shift
fi

LOCAL_PATH="$1"
REMOTE_PATH="$2"

scp $RECURSIVE $SSH_OPTS "$LOCAL_PATH" "$SSH_HOST:$REMOTE_PATH"
