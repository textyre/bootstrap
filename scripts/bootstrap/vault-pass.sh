#!/bin/bash
set -e

# Cascading vault password resolver
# Used by ansible.cfg: vault_password_file = ./vault-pass.sh
#
# Priority:
#   1. GNU Password Store (pass) — GPG-encrypted
#   2. Local file ~/.vault-pass — chmod 600
#   3. Error with setup instructions

# 1. Try GNU Password Store (GPG-encrypted)
if command -v pass &>/dev/null; then
    pass show ansible/vault-password 2>/dev/null && exit 0
fi

# 2. Try local file
if [ -f "${HOME}/.vault-pass" ]; then
    cat "${HOME}/.vault-pass"
    exit 0
fi

# 3. Fail with clear instructions
echo "ERROR: Vault password not found." >&2
echo "Setup options:" >&2
echo "  1. echo 'your_vault_password' > ~/.vault-pass && chmod 600 ~/.vault-pass" >&2
echo "  2. pass insert ansible/vault-password" >&2
exit 1
