#!/usr/bin/env bash
# ssh-scp-to.sh - Copy files TO the VM
#
# Usage:
#   ./scripts/ssh-scp-to.sh --project              # Sync entire project
#   ./scripts/ssh-scp-to.sh [-r] <src>... <dest>   # Copy specific files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
REMOTE_BASE="/home/textyre/bootstrap"

# Project sync mode
if [[ "${1:-}" == "--project" ]]; then
    echo "==> Syncing project to ${SSH_HOST}:${REMOTE_BASE}"
    ssh $SSH_OPTS "$SSH_HOST" \
        "find ${REMOTE_BASE} -delete 2>/dev/null; rm -rf ${REMOTE_BASE} 2>/dev/null; true"

    PROJECT_DIRS=(ansible dotfiles scripts)
    PROJECT_FILES=(Taskfile.yml bootstrap.sh AGENTS.md CLAUDE.md)

    for dir in "${PROJECT_DIRS[@]}"; do
        echo "  copying ${dir}/"
        ssh $SSH_OPTS "$SSH_HOST" "mkdir -p ${REMOTE_BASE}/${dir}"
        scp -v -r $SSH_OPTS "${REPO_ROOT}/${dir}" "$SSH_HOST:${REMOTE_BASE}/"
    done

    for file in "${PROJECT_FILES[@]}"; do
        if [[ -f "${REPO_ROOT}/${file}" ]]; then
            echo "  copying ${file}"
            scp -v $SSH_OPTS "${REPO_ROOT}/${file}" "$SSH_HOST:${REMOTE_BASE}/"
        fi
    done

    # Fix permissions (Windows scp sets world-writable which breaks ansible.cfg)
    echo "  fixing directory permissions"
    ssh $SSH_OPTS "$SSH_HOST" "chmod -R u+rwX,go+rX,go-w ${REMOTE_BASE}"
    echo "  fixing script permissions"
    ssh $SSH_OPTS "$SSH_HOST" \
        "chmod +x ${REMOTE_BASE}/bootstrap.sh \
                  ${REMOTE_BASE}/scripts/*.sh \
                  ${REMOTE_BASE}/ansible/vault-pass.sh"

    echo "==> Sync complete"
    exit 0
fi

# Manual mode
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 --project" >&2
    echo "       $0 [-r] <local-path>... <remote-path>" >&2
    exit 1
fi

RECURSIVE=""
if [[ "$1" == "-r" ]]; then
    RECURSIVE="-r"
    shift
fi

ARGS=("$@")
REMOTE_PATH="${ARGS[-1]}"
LOCAL_PATHS=("${ARGS[@]:0:$#-1}")

ssh $SSH_OPTS "$SSH_HOST" "mkdir -p '$REMOTE_PATH'"
scp -v $RECURSIVE $SSH_OPTS "${LOCAL_PATHS[@]}" "$SSH_HOST:$REMOTE_PATH"
