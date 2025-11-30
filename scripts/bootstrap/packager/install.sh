#!/usr/bin/env bash
set -eu

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
EXTERNALS_ROOT="${1:-}"

# Always write to the packager-specific log file so install runs have their
# own logs. This appends to `scripts/bootstrap/log/install.log` and still
# leaves stdout/stderr on the console (so parent bootstraps also capture it).
LOG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/log"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/install.log"
export LOG_FILE="$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

. "${SCRIPT_DIR}/packages.sh"
if [ ! -f "$SCRIPT_DIR/packages.sh" ]; then
  echo "ERROR: required config not found: $SCRIPT_DIR/packages.sh" >&2
  echo "Create a bash file defining the array 'packages=(pkg1 pkg2 ...)' (packages.sh)." >&2
  exit 3
fi

. "$SCRIPT_DIR/packages.sh"
if [ "${#packages[@]}" -eq 0 ]; then
  echo "No packages defined in host-packages.sh (array 'packages' is empty)." >&2
  exit 0
fi

PACKAGES="${packages[*]}"

if [ -z "${PACKAGES:-}" ]; then
  echo "No packages to install (empty config)." >&2
  exit 0
fi

# Source packager entrypoint which provides pm_update/pm_install for the
# detected distro. packager.sh will auto-select a suitable distro script.
. "$SCRIPT_DIR/packager.sh" || true

echo "Using packager for distro: ${DISTRO:-unknown}"
echo "Updating package database..."
# Use pm_update helper from pkg-manager.sh. If EXTERNALS_ROOT is set the
# update will target that root (for pacman/ dnf implementations).
pm_update "${EXTERNALS_ROOT:-}"

echo "Installing packages: $PACKAGES"

# Use pm_install helper from packager. Pass EXTERNALS_ROOT as first
# arg so installs go into externals when configured by bootstrap.sh.
pm_install "${EXTERNALS_ROOT:-}" $PACKAGES

# Cleanup mounted pseudo-filesystems
pm_cleanup_root "${EXTERNALS_ROOT:-}"

echo "Done."

