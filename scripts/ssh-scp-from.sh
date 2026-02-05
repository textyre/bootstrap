#!/usr/bin/env bash
# ssh-scp-from.sh - Copy files FROM the VM
#
# Usage:
#   ./scripts/ssh-scp-from.sh <remote-path> <local-path>
#   ./scripts/ssh-scp-from.sh /home/user/file.txt ./
#   ./scripts/ssh-scp-from.sh -r /home/user/dir/ ./dir/

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 [-r] <remote-path> <local-path>" >&2
    echo "  -r  Copy directories recursively" >&2
    exit 1
fi

RECURSIVE=""
if [[ "$1" == "-r" ]]; then
    RECURSIVE="-r"
    shift
fi

REMOTE_PATH="$1"
LOCAL_PATH="$2"

scp $RECURSIVE $SSH_OPTS "$SSH_HOST:$REMOTE_PATH" "$LOCAL_PATH"
