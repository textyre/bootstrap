#!/usr/bin/env bash
# ssh-scp-from.sh - Copy files FROM the VM
#
# Usage:
#   ./scripts/ssh-scp-from.sh <remote-path> <local-path>
#   ./scripts/ssh-scp-from.sh /home/user/file.txt ./
#   ./scripts/ssh-scp-from.sh -r /home/user/dir/ ./dir/

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_PORT="${SSH_PORT:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_127.0.0.1_2222}"
SCP_OPTS=(-o BatchMode=yes -o ConnectTimeout=60)
SSH_TARGET="${SSH_HOST}"

if [[ -n "${SSH_PORT}" ]]; then
    SCP_OPTS+=(-P "${SSH_PORT}")
fi
if [[ -f "${SSH_KEY}" ]]; then
    SCP_OPTS+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)
fi
if [[ -n "${SSH_USER}" && "${SSH_HOST}" != *@* ]]; then
    SSH_TARGET="${SSH_USER}@${SSH_HOST}"
fi

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

scp $RECURSIVE "${SCP_OPTS[@]}" "$SSH_TARGET:$REMOTE_PATH" "$LOCAL_PATH"
