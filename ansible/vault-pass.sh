#!/bin/bash
set -euo pipefail

# Ansible's password-file interface reads the ephemeral runtime credential.
# The host-side secret store resolves local files; no secret file is delivered.

if [[ -n "${BOOTSTRAP_VAULT_PASSWORD:-}" ]]; then
    printf '%s\n' "${BOOTSTRAP_VAULT_PASSWORD}"
    exit 0
fi

echo "ERROR: Supply BOOTSTRAP_VAULT_PASSWORD through the OpenStrap runtime secret store." >&2
exit 1
