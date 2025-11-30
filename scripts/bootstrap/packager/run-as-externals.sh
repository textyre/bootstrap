#!/usr/bin/env bash
# run-as-externals.sh - Run package operations as dedicated externals user
set -eu

EXTERNALS_USER="${EXTERNALS_USER:-externals}"
SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if [ "$(whoami)" = "$EXTERNALS_USER" ]; then
  # Already running as externals user, execute install directly
  exec "$SCRIPT_DIR/packager/install.sh" "$@"
else
  # Need to switch to externals user
  if ! id "$EXTERNALS_USER" &>/dev/null; then
    echo "ERROR: User $EXTERNALS_USER does not exist." >&2
    echo "Run setup-externals-user.sh first." >&2
    exit 1
  fi
  
  echo "Switching to user $EXTERNALS_USER for package operations..."
  exec sudo -u "$EXTERNALS_USER" "$SCRIPT_DIR/packager/install.sh" "$@"
fi
