#!/usr/bin/env bash
# ssh-scp-to.sh - Copy files TO the VM
#
# Usage:
#   ./scripts/ssh-scp-to.sh --project              # Sync entire project
#   ./scripts/ssh-scp-to.sh --project --bootstrap  # Sync project and rebuild VM venv
#   ./scripts/ssh-scp-to.sh [-r] <src>... <dest>   # Copy specific files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_PORT="${SSH_PORT:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_127.0.0.1_2222}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=60)
SCP_OPTS=(-o BatchMode=yes -o ConnectTimeout=60)
SSH_TARGET="${SSH_HOST}"
REMOTE_BASE="/home/textyre/bootstrap"
TAR_BIN="tar"

if [[ -x /usr/bin/tar ]]; then
    TAR_BIN="/usr/bin/tar"
fi

if [[ -n "${SSH_PORT}" ]]; then
    SSH_OPTS+=(-p "${SSH_PORT}")
    SCP_OPTS+=(-P "${SSH_PORT}")
fi
if [[ -f "${SSH_KEY}" ]]; then
    SSH_OPTS+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)
    SCP_OPTS+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)
fi
if [[ -n "${SSH_USER}" && "${SSH_HOST}" != *@* ]]; then
    SSH_TARGET="${SSH_USER}@${SSH_HOST}"
fi

# Project sync mode
if [[ "${1:-}" == "--project" ]]; then
    shift

    RUN_BOOTSTRAP=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bootstrap)
                RUN_BOOTSTRAP=1
                ;;
            *)
                echo "Unknown --project option: $1" >&2
                exit 1
                ;;
        esac
        shift
    done

    echo "==> Syncing project to ${SSH_TARGET}:${REMOTE_BASE}"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        "find '${REMOTE_BASE}' -delete 2>/dev/null; rm -rf '${REMOTE_BASE}' 2>/dev/null; true"

    PROJECT_DIRS=(ansible dotfiles scripts greeter)
    PROJECT_FILES=(Taskfile.yml bootstrap.sh AGENTS.md CLAUDE.md)

    for dir in "${PROJECT_DIRS[@]}"; do
        echo "  copying ${dir}/"
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p ${REMOTE_BASE}/${dir}"
        if [[ "$dir" == "ansible" ]]; then
            # Use tar to exclude platform-specific artifacts that must not reach the VM
            (cd "${REPO_ROOT}" && "${TAR_BIN}" cf - \
                --exclude='ansible/.venv' \
                --exclude='ansible/__pycache__' \
                --exclude='ansible/.molecule' \
                --exclude='ansible/.vault-pass' \
                --exclude='ansible/*.vault-pass' \
                "${dir}/") | \
                ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "tar xf - -C ${REMOTE_BASE}/"
        elif [[ "$dir" == "greeter" ]]; then
            # Build artefacts are created on the VM by the Taskfile before workstation runs.
            (cd "${REPO_ROOT}" && "${TAR_BIN}" cf - \
                --exclude='greeter/node_modules' \
                --exclude='greeter/dist' \
                "${dir}/") | \
                ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "tar xf - -C ${REMOTE_BASE}/"
        else
            scp -v -r "${SCP_OPTS[@]}" "${REPO_ROOT}/${dir}" "$SSH_TARGET:${REMOTE_BASE}/"
        fi
    done

    for file in "${PROJECT_FILES[@]}"; do
        if [[ -f "${REPO_ROOT}/${file}" ]]; then
            echo "  copying ${file}"
            scp -v "${SCP_OPTS[@]}" "${REPO_ROOT}/${file}" "$SSH_TARGET:${REMOTE_BASE}/"
        fi
    done

    # Fix permissions (Windows scp sets world-writable which breaks ansible.cfg)
    echo "  fixing directory permissions"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod -R u+rwX,go+rX,go-w ${REMOTE_BASE}"
    echo "  fixing script permissions"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        "chmod +x ${REMOTE_BASE}/bootstrap.sh \
                  ${REMOTE_BASE}/scripts/*.sh \
                  ${REMOTE_BASE}/ansible/vault-pass.sh"

    if [[ "${RUN_BOOTSTRAP}" -eq 1 ]]; then
        echo "  bootstrapping remote ansible environment"
        SSH_HOST="${SSH_HOST}" SSH_PORT="${SSH_PORT}" SSH_USER="${SSH_USER}" SSH_KEY="${SSH_KEY}" \
            "${SCRIPT_DIR}/ssh-run.sh" --bootstrap-secrets \
            "cd ${REMOTE_BASE} && scripts/setup-venv.sh && scripts/setup-galaxy.sh"
    fi

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

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_PATH'"
scp -v $RECURSIVE "${SCP_OPTS[@]}" "${LOCAL_PATHS[@]}" "$SSH_TARGET:$REMOTE_PATH"
