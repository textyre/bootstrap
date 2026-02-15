#!/usr/bin/env bash
# Create Python virtualenv and install pip dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
VENV_DIR="${ANSIBLE_DIR}/.venv"

if [[ -d "${VENV_DIR}" ]]; then
    echo "==> Python venv already exists"
    exit 0
fi

echo "==> Creating Python virtualenv..."
python -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${ANSIBLE_DIR}/requirements.txt"
echo "==> Python venv ready"
exit 0
