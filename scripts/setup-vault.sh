#!/usr/bin/env bash
# Create encrypted vault.yml with ansible_become_password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"
REPO_ROOT="${BOOTSTRAP_REPO_ROOT}"
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
sudo_pass="$(bootstrap_sudo_password)"
export BOOTSTRAP_RENDER_SUDO_PASS="${sudo_pass}"
python3 - <<'PY' | "${ANSIBLE_VAULT}" encrypt \
    --vault-password-file "${VAULT_PASS_SCRIPT}" \
    --output "${VAULT_FILE}" -
import json
import os

value = os.environ["BOOTSTRAP_RENDER_SUDO_PASS"]
print(f"ansible_become_password: {json.dumps(value)}")
PY
chmod 600 "${VAULT_FILE}"
unset sudo_pass BOOTSTRAP_RENDER_SUDO_PASS
echo "==> vault.yml created and encrypted"
exit 0
