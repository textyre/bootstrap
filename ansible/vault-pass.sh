#!/bin/bash
set -euo pipefail

# Project bootstrap vault password resolver
# Used by ansible.cfg: vault_password_file = ./vault-pass.sh
#
# Sources:
#   1. BOOTSTRAP_VAULT_PASSWORD env var
#   2. BOOTSTRAP_VAULT_PASSWORD_GPG_FILE
#   3. BOOTSTRAP_VAULT_PASSWORD_FILE (compatibility fallback)
#   3. Error with setup instructions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/bootstrap-env.sh"

if [[ -n "${BOOTSTRAP_VAULT_PASSWORD:-}" ]]; then
    printf '%s\n' "${BOOTSTRAP_VAULT_PASSWORD}"
    exit 0
fi

if [[ -n "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE:-}" && -f "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}" ]]; then
    gpg --quiet --batch --decrypt -- "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}"
    exit 0
fi

if [[ -n "${BOOTSTRAP_VAULT_PASSWORD_FILE:-}" && -f "${BOOTSTRAP_VAULT_PASSWORD_FILE}" ]]; then
    cat "${BOOTSTRAP_VAULT_PASSWORD_FILE}"
    exit 0
fi

echo "ERROR: Vault password not found." >&2
echo "Setup options:" >&2
echo "  1. Copy scripts/bootstrap.env.example to .local/bootstrap/bootstrap.env" >&2
echo "  2. Export BOOTSTRAP_VAULT_PASSWORD or set BOOTSTRAP_VAULT_PASSWORD_GPG_FILE" >&2
echo "  3. Run scripts/setup-vault-pass.sh to create the local encrypted secret" >&2
exit 1
