#!/usr/bin/env bash
# ssh-run.sh - Execute commands on VM via SSH
#
# Usage:
#   ./scripts/ssh-run.sh <command>
#   ./scripts/ssh-run.sh --bootstrap-secrets <command>
#   ./scripts/ssh-run.sh "ls -la"
#   ./scripts/ssh-run.sh "df -h && free -m"
#
# Environment variables:
#   SSH_HOST - override default host (default: arch-127.0.0.1-2222)
#   SSH_PORT - optional SSH port for direct 127.0.0.1 clone connections
#   SSH_USER - optional SSH user for direct host connections
#   SSH_KEY  - optional identity file (defaults to clone test key when present)

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_PORT="${SSH_PORT:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_127.0.0.1_2222}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=60)
SSH_TARGET="${SSH_HOST}"

if [[ -n "${SSH_PORT}" ]]; then
    SSH_OPTS+=(-p "${SSH_PORT}")
fi
if [[ -f "${SSH_KEY}" ]]; then
    SSH_OPTS+=(-i "${SSH_KEY}" -o IdentitiesOnly=yes)
fi
if [[ -n "${SSH_USER}" && "${SSH_HOST}" != *@* ]]; then
    SSH_TARGET="${SSH_USER}@${SSH_HOST}"
fi
FORWARD_BOOTSTRAP_SECRETS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bootstrap-secrets)
            FORWARD_BOOTSTRAP_SECRETS=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command>" >&2
    echo "       $0 --bootstrap-secrets <command>" >&2
    echo "Example: $0 'ls -la'" >&2
    exit 1
fi

COMMAND="$*"
VAULT_PASS=""
SUDO_PASS=""

ssh_exec() {
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$1"
}

run_remote_command() {
    local remote_command="$1"

    if [[ "${FORWARD_BOOTSTRAP_SECRETS}" -eq 0 ]]; then
        ssh_exec "${remote_command}"
        return $?
    fi

    local remote_command_quoted
    local remote_wrapper
    local remote_wrapper_quoted

    printf -v remote_command_quoted '%q' "${remote_command}"
    remote_wrapper='IFS= read -r -d "" BOOTSTRAP_VAULT_PASSWORD; IFS= read -r -d "" BOOTSTRAP_SUDO_PASSWORD; export BOOTSTRAP_VAULT_PASSWORD BOOTSTRAP_SUDO_PASSWORD; exec bash -lc "$1"'
    printf -v remote_wrapper_quoted '%q' "${remote_wrapper}"

    printf '%s\0%s\0' "${VAULT_PASS}" "${SUDO_PASS}" | \
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "bash -c ${remote_wrapper_quoted} _ ${remote_command_quoted}"
}

if [[ "${FORWARD_BOOTSTRAP_SECRETS}" -eq 1 ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/bootstrap-env.sh"
    VAULT_PASS="$(bootstrap_vault_password)"
    SUDO_PASS="$(bootstrap_sudo_password)"
fi

run_remote_command "${COMMAND}"
