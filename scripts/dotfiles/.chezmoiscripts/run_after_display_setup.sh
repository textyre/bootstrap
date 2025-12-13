#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/../../bootstrap" && pwd)"

if [ -f "$BOOTSTRAP_DIR/gui/deploy_dotfiles.py" ]; then
    python3 "$BOOTSTRAP_DIR/gui/deploy_dotfiles.py" "${SUDO_USER:-$USER}"
fi

exit 0
