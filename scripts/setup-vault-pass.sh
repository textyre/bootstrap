#!/usr/bin/env bash
# Create ~/.vault-pass file for Ansible vault encryption

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VAULT_PASS_FILE="${HOME}/.vault-pass"

if [[ -f "${VAULT_PASS_FILE}" ]]; then
    echo "==> Vault password already configured"
    exit 0
fi

read -s -r -p "Enter vault/sudo password: " vault_pass
echo
echo "${vault_pass}" > "${VAULT_PASS_FILE}"
chmod 600 "${VAULT_PASS_FILE}"
unset vault_pass
echo "==> Vault password saved to ${VAULT_PASS_FILE}"
exit 0
