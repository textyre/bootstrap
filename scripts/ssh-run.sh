#!/usr/bin/env bash
# ssh-run.sh - Execute commands on VM via SSH
#
# Usage:
#   ./scripts/ssh-run.sh <command>
#   ./scripts/ssh-run.sh --bootstrap-secrets <command>
#   ./scripts/ssh-run.sh --bootstrap-secrets --retry-on-kernel-mismatch <command>
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
RETRY_ON_KERNEL_MISMATCH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bootstrap-secrets)
            FORWARD_BOOTSTRAP_SECRETS=1
            shift
            ;;
        --retry-on-kernel-mismatch)
            RETRY_ON_KERNEL_MISMATCH=1
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
    echo "       $0 --bootstrap-secrets --retry-on-kernel-mismatch <command>" >&2
    echo "Example: $0 'ls -la'" >&2
    exit 1
fi

if [[ "${RETRY_ON_KERNEL_MISMATCH}" -eq 1 && "${FORWARD_BOOTSTRAP_SECRETS}" -eq 0 ]]; then
    echo "ERROR: --retry-on-kernel-mismatch requires --bootstrap-secrets." >&2
    exit 1
fi

COMMAND="$*"
VAULT_PASS=""
SUDO_PASS=""

ssh_exec() {
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "$1"
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
        ssh "${SSH_OPTS[@]}" "$SSH_HOST" "bash -c ${remote_wrapper_quoted} _ ${remote_command_quoted}"
}

ssh_can_connect() {
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "true" >/dev/null 2>&1
}

remote_running_kernel_has_matching_modules() {
    run_remote_command 'test -d "/usr/lib/modules/$(uname -r)"' >/dev/null 2>&1
}

wait_for_ssh_state() {
    local desired_state="$1"
    local max_attempts="$2"
    local delay_seconds="$3"
    local attempt=1

    while (( attempt <= max_attempts )); do
        if ssh_can_connect; then
            if [[ "${desired_state}" == "up" ]]; then
                return 0
            fi
        elif [[ "${desired_state}" == "down" ]]; then
            return 0
        fi

        sleep "${delay_seconds}"
        (( attempt += 1 ))
    done

    return 1
}

schedule_remote_reboot() {
    run_remote_command "printf '%s\\n' \"\$BOOTSTRAP_SUDO_PASSWORD\" | sudo -S -p '' -- systemd-run --unit bootstrap-kernel-mismatch-reboot --on-active=2 /usr/bin/systemctl reboot" >/dev/null
}

run_with_optional_kernel_retry() {
    local rc

    if run_remote_command "${COMMAND}"; then
        return 0
    fi
    rc=$?

    if [[ "${RETRY_ON_KERNEL_MISMATCH}" -eq 0 ]]; then
        return "${rc}"
    fi

    if ! ssh_can_connect; then
        return "${rc}"
    fi

    if remote_running_kernel_has_matching_modules; then
        return "${rc}"
    fi

    echo "NOTICE: Remote command failed after the running kernel lost its matching modules directory." >&2
    echo "NOTICE: Rebooting the disposable VM once and retrying the same command." >&2

    schedule_remote_reboot

    if ! wait_for_ssh_state down 24 5; then
        echo "ERROR: SSH never went down after scheduling the remote reboot." >&2
        return "${rc}"
    fi

    if ! wait_for_ssh_state up 48 5; then
        echo "ERROR: SSH did not return after the remote reboot." >&2
        return "${rc}"
    fi

    run_remote_command "${COMMAND}"
}

if [[ "${FORWARD_BOOTSTRAP_SECRETS}" -eq 1 ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/bootstrap-env.sh"
    VAULT_PASS="$(bootstrap_vault_password)"
    SUDO_PASS="$(bootstrap_sudo_password)"
fi

run_with_optional_kernel_retry
