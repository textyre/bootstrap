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

set -euo pipefail

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_PORT="${SSH_PORT:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=60)

if [[ -n "${SSH_PORT}" ]]; then
    SSH_OPTS+=(-p "${SSH_PORT}")
fi
FORWARD_BOOTSTRAP_SECRETS=0

if [[ "${1:-}" == "--bootstrap-secrets" ]]; then
    FORWARD_BOOTSTRAP_SECRETS=1
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command>" >&2
    echo "       $0 --bootstrap-secrets <command>" >&2
    echo "Example: $0 'ls -la'" >&2
    exit 1
fi

COMMAND="$*"

if [[ "${FORWARD_BOOTSTRAP_SECRETS}" -eq 0 ]]; then
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "$COMMAND"
    exit 0
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

VAULT_PASS="$(bootstrap_vault_password)"
SUDO_PASS="$(bootstrap_sudo_password)"
printf -v REMOTE_COMMAND '%q' "${COMMAND}"
REMOTE_WRAPPER='IFS= read -r -d "" BOOTSTRAP_VAULT_PASSWORD; IFS= read -r -d "" BOOTSTRAP_SUDO_PASSWORD; export BOOTSTRAP_VAULT_PASSWORD BOOTSTRAP_SUDO_PASSWORD; exec bash -lc "$1"'
printf -v REMOTE_WRAPPER_QUOTED '%q' "${REMOTE_WRAPPER}"

printf '%s\0%s\0' "${VAULT_PASS}" "${SUDO_PASS}" | \
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "bash -c ${REMOTE_WRAPPER_QUOTED} _ ${REMOTE_COMMAND}"
