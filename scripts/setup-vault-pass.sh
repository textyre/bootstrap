#!/usr/bin/env bash
# Create ~/.vault-pass file for Ansible vault encryption

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VAULT_PASS_FILE="${HOME}/.vault-pass"
PROJECT_VAULT_PASS="${ANSIBLE_DIR}/.vault-pass"

if [[ -f "${VAULT_PASS_FILE}" ]]; then
    echo "==> Vault password already configured"
    exit 0
fi

# 1. Copy from project if available
if [[ -f "${PROJECT_VAULT_PASS}" ]]; then
    cp "${PROJECT_VAULT_PASS}" "${VAULT_PASS_FILE}"
    chmod 600 "${VAULT_PASS_FILE}"
    echo "==> Vault password copied from project"
    exit 0
fi

# 2. Accept from env or argument
vault_pass="${1:-${VAULT_PASS:-}}"

# 3. Interactive fallback
if [[ -z "${vault_pass}" ]]; then
    read -s -r -p "Enter vault/sudo password: " vault_pass
    echo
fi

echo "${vault_pass}" > "${VAULT_PASS_FILE}"
chmod 600 "${VAULT_PASS_FILE}"
unset vault_pass
echo "==> Vault password saved to ${VAULT_PASS_FILE}"
exit 0
