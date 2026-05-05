#!/usr/bin/env bash
# ssh-scp-to.sh - Copy files TO the VM
#
# Usage:
#   ./scripts/ssh-scp-to.sh --project              # Sync entire project
#   ./scripts/ssh-scp-to.sh --project --clean-venv # Sync project and rebuild venv later
#   ./scripts/ssh-scp-to.sh [-r] <src>... <dest>   # Copy specific files
#
# Environment:
#   BOOTSTRAP_SYNC_PRESERVE_REMOTE_VENV=0 disables preserving the VM's Linux venv.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_PORT="${SSH_PORT:-}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=60)
REMOTE_BASE="/home/textyre/bootstrap"

if [[ -n "${SSH_PORT}" ]]; then
    SSH_OPTS+=(-P "${SSH_PORT}")
fi

# Project sync mode
if [[ "${1:-}" == "--project" ]]; then
    shift

    PRESERVE_REMOTE_VENV="${BOOTSTRAP_SYNC_PRESERVE_REMOTE_VENV:-1}"
    REMOTE_VENV_STASH=""
    REMOTE_VENV_STASH_ACTIVE=0

    restore_remote_venv() {
        if [[ "${PRESERVE_REMOTE_VENV}" != "0" && "${REMOTE_VENV_STASH_ACTIVE}" -eq 1 ]]; then
            ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" \
                "if [ -d '${REMOTE_VENV_STASH}' ]; then mkdir -p '${REMOTE_BASE}/ansible'; rm -rf '${REMOTE_BASE}/ansible/.venv'; mv '${REMOTE_VENV_STASH}' '${REMOTE_BASE}/ansible/.venv'; fi" \
                2>/dev/null || true
        fi
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean-venv|--no-preserve-venv)
                PRESERVE_REMOTE_VENV=0
                ;;
            *)
                echo "Unknown --project option: $1" >&2
                exit 1
                ;;
        esac
        shift
    done

    echo "==> Syncing project to ${SSH_HOST}:${REMOTE_BASE}"
    REMOTE_VENV_STASH="/tmp/bootstrap-ansible-venv-${RANDOM}-${RANDOM}"
    if [[ "${PRESERVE_REMOTE_VENV}" != "0" ]]; then
        echo "  preserving remote ansible/.venv"
        ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" \
            "if [ -d '${REMOTE_BASE}/ansible/.venv' ]; then rm -rf '${REMOTE_VENV_STASH}'; mv '${REMOTE_BASE}/ansible/.venv' '${REMOTE_VENV_STASH}'; fi"
        REMOTE_VENV_STASH_ACTIVE=1
        trap restore_remote_venv EXIT
    fi

    ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" \
        "find '${REMOTE_BASE}' -delete 2>/dev/null; rm -rf '${REMOTE_BASE}' 2>/dev/null; true"

    PROJECT_DIRS=(ansible dotfiles scripts)
    PROJECT_FILES=(Taskfile.yml bootstrap.sh AGENTS.md CLAUDE.md)

    for dir in "${PROJECT_DIRS[@]}"; do
        echo "  copying ${dir}/"
        ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" "mkdir -p ${REMOTE_BASE}/${dir}"
        if [[ "$dir" == "ansible" ]]; then
            # Use tar to exclude platform-specific artifacts that must not reach the VM
            (cd "${REPO_ROOT}" && tar cf - \
                --exclude='ansible/.venv' \
                --exclude='ansible/__pycache__' \
                --exclude='ansible/.molecule' \
                --exclude='ansible/.vault-pass' \
                --exclude='ansible/*.vault-pass' \
                "${dir}/") | \
                ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" "tar xf - -C ${REMOTE_BASE}/"
        else
            scp -v -r "${SSH_OPTS[@]}" "${REPO_ROOT}/${dir}" "$SSH_HOST:${REMOTE_BASE}/"
        fi
    done

    for file in "${PROJECT_FILES[@]}"; do
        if [[ -f "${REPO_ROOT}/${file}" ]]; then
            echo "  copying ${file}"
            scp -v "${SSH_OPTS[@]}" "${REPO_ROOT}/${file}" "$SSH_HOST:${REMOTE_BASE}/"
        fi
    done

    if [[ "${PRESERVE_REMOTE_VENV}" != "0" ]]; then
        echo "  restoring remote ansible/.venv"
        restore_remote_venv
        REMOTE_VENV_STASH_ACTIVE=0
        trap - EXIT
    fi

    # Fix permissions (Windows scp sets world-writable which breaks ansible.cfg)
    echo "  fixing directory permissions"
    ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" "chmod -R u+rwX,go+rX,go-w ${REMOTE_BASE}"
    echo "  fixing script permissions"
    ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" \
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

ssh "${SSH_OPTS[@]/-P/-p}" "$SSH_HOST" "mkdir -p '$REMOTE_PATH'"
scp -v $RECURSIVE "${SSH_OPTS[@]}" "${LOCAL_PATHS[@]}" "$SSH_HOST:$REMOTE_PATH"
