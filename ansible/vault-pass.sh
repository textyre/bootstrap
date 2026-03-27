#!/bin/bash
set -e

# Cascading vault password resolver
# Used by ansible.cfg: vault_password_file = ./vault-pass.sh
#
# Priority:
#   1. Project-local .vault-pass (next to this script)
#   2. GNU Password Store (pass) — GPG-encrypted
#   3. Home directory ~/.vault-pass
#   4. Error with setup instructions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Try project-local file
if [ -f "${SCRIPT_DIR}/.vault-pass" ]; then
    cat "${SCRIPT_DIR}/.vault-pass"
    exit 0
fi

# 2. Try GNU Password Store (GPG-encrypted)
if command -v pass &>/dev/null; then
    pass show ansible/vault-password 2>/dev/null && exit 0
fi

# 3. Try home directory
if [ -f "${HOME}/.vault-pass" ]; then
    cat "${HOME}/.vault-pass"
    exit 0
fi

# 4. Fail with clear instructions
echo "ERROR: Vault password not found." >&2
echo "Setup options:" >&2
echo "  1. Place .vault-pass in the ansible/ directory" >&2
echo "  2. pass insert ansible/vault-password" >&2
exit 1
