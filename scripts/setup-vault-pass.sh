#!/usr/bin/env bash
# Create a GPG-encrypted project-local vault password secret for Ansible vault.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/bootstrap-env.sh"

bootstrap_mkdir_secure_dir

if [[ -f "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}" ]]; then
    echo "==> Vault password already configured at ${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}"
    exit 0
fi

vault_pass="${1:-${BOOTSTRAP_VAULT_PASSWORD:-}}"

if [[ -z "${vault_pass}" ]]; then
    read -s -r -p "Enter vault/sudo password: " vault_pass
    echo
fi

recipient="${BOOTSTRAP_VAULT_GPG_RECIPIENT:-$(bootstrap_default_gpg_recipient || true)}"

if [[ -z "${recipient}" ]]; then
    echo "ERROR: No GPG recipient configured and no local secret key found." >&2
    echo "Set BOOTSTRAP_VAULT_GPG_RECIPIENT or create a local GPG secret key first." >&2
    exit 1
fi

printf '%s' "${vault_pass}" | gpg --batch --yes --quiet --encrypt \
    --recipient "${recipient}" \
    --output "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}" -
chmod 600 "${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}" 2>/dev/null || true
unset vault_pass
echo "==> Vault password encrypted to ${BOOTSTRAP_VAULT_PASSWORD_GPG_FILE}"
exit 0
