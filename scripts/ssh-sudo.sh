#!/usr/bin/env bash
# ssh-sudo.sh - Execute sudo commands on VM using local project bootstrap secrets
#
# Usage:
#   ./scripts/ssh-sudo.sh <command>
#   ./scripts/ssh-sudo.sh "systemctl restart sshd"
#   ./scripts/ssh-sudo.sh "pacman -Syu --noconfirm"
#
# The script:
# 1. Resolves sudo password from BOOTSTRAP_SUDO_PASSWORD[_FILE] or
#    BOOTSTRAP_VAULT_PASSWORD[_FILE] on the local project side
# 2. Pipes the password directly to sudo over SSH
# 3. Leaves no persistent sudo password artifact on the VM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

SSH_HOST="${SSH_HOST:-arch-127.0.0.1-2222}"
SSH_PORT="${SSH_PORT:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_127.0.0.1_2222}"
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

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command>" >&2
    echo "Example: $0 'systemctl restart sshd'" >&2
    exit 1
fi

COMMAND="$*"
SUDO_PASS="$(bootstrap_sudo_password)"
REMOTE_COMMAND="$(printf 'sudo -S -p %q -- bash -lc %q' '' "$COMMAND")"

printf '%s\n' "${SUDO_PASS}" | ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "${REMOTE_COMMAND}"
