#!/usr/bin/env bash
# Install Ansible Galaxy collections

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VENV_DIR="${ANSIBLE_DIR}/.venv"
GALAXY="${VENV_DIR}/bin/ansible-galaxy"

if [[ ! -x "${GALAXY}" ]]; then
    GALAXY="$(command -v ansible-galaxy 2>/dev/null || true)"
    if [[ -z "${GALAXY}" ]]; then
        echo "ERROR: ansible-galaxy not found. Run scripts/setup-venv.sh first." >&2
        exit 1
    fi
fi

echo "==> Installing Galaxy collections..."
"${GALAXY}" collection install -r "${ANSIBLE_DIR}/requirements.yml"
echo "==> Galaxy collections ready"
exit 0
