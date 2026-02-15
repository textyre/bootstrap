#!/usr/bin/env bash
# Create encrypted vault.yml with ansible_become_password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VAULT_FILE="${ANSIBLE_DIR}/inventory/group_vars/all/vault.yml"
VAULT_PASS_SCRIPT="${ANSIBLE_DIR}/vault-pass.sh"
VENV_DIR="${ANSIBLE_DIR}/.venv"

if [[ -f "${VAULT_FILE}" ]]; then
    echo "==> vault.yml already exists"
    exit 0
fi

# Check prerequisites
if ! "${VAULT_PASS_SCRIPT}" >/dev/null 2>&1; then
    echo "ERROR: Vault password not configured. Run scripts/setup-vault-pass.sh first." >&2
    exit 1
fi

ANSIBLE_VAULT="${VENV_DIR}/bin/ansible-vault"
if [[ ! -x "${ANSIBLE_VAULT}" ]]; then
    # Try system ansible-vault
    ANSIBLE_VAULT="$(command -v ansible-vault 2>/dev/null || true)"
    if [[ -z "${ANSIBLE_VAULT}" ]]; then
        echo "ERROR: ansible-vault not found. Run scripts/setup-venv.sh first." >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "${VAULT_FILE}")"
read -s -r -p "Enter sudo password for ansible_become_password: " sudo_pass
echo
echo "ansible_become_password: \"${sudo_pass}\"" | \
    "${ANSIBLE_VAULT}" encrypt \
        --vault-password-file "${VAULT_PASS_SCRIPT}" \
        --output "${VAULT_FILE}" -
chmod 600 "${VAULT_FILE}"
unset sudo_pass
echo "==> vault.yml created and encrypted"
exit 0
