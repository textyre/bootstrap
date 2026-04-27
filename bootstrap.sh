#!/usr/bin/env bash
# =============================================================================
# Arch Linux Workstation Bootstrap
# =============================================================================
# Arch Linux Workstation Bootstrap — full setup + playbook run.
# For individual steps, use scripts/ directly.
#
# Usage:
#   ./bootstrap.sh                        # Full setup
#   ./bootstrap.sh --tags packages        # Only packages
#   ./bootstrap.sh --tags "docker,ssh"    # Docker + SSH
#   ./bootstrap.sh --check                # Dry-run
#   ./bootstrap.sh --skip-tags firewall   # Skip firewall
#
# All arguments are passed directly to ansible-playbook.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/scripts/install-deps.sh"
"${SCRIPT_DIR}/scripts/setup-venv.sh"
"${SCRIPT_DIR}/scripts/setup-galaxy.sh"

echo "==> Running workstation playbook..."
cd "${SCRIPT_DIR}"
task --yes workstation -- "$@"

echo "==> Bootstrap complete!"
