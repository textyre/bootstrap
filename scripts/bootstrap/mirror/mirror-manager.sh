#!/usr/bin/env bash
set -euo pipefail

# mirror-manager.sh
# Unified mirror selection orchestrator for all supported distros.
# Determines distro, parses CLI flags, and invokes distro-specific mirror script.
#
# Usage:
#   mirror-manager.sh [OPTIONS]
#
# Options:
#   --distro DISTRO          Force distro detection (arch, ubuntu, fedora, gentoo)
#   --protocol PROTO         Protocol preference: https, http (default: https)
#   --latest N               Select N latest mirrors (default: 5)
#   --age N                  Max mirror age in hours (default: 12)
#   --sort-by METHOD         Sort by: rate, age, location (default: rate)
#   --country CODE           Country code for geolocation (default: KZ; KZ, RU, DE, FR, NL)
#   --validate               Validate mirror accessibility before using
#   --debug                  Enable debug logging
#   -h, --help               Show this help message

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Source common utilities
. "$SCRIPT_DIR/mirror-common.sh" || {
  echo "ERROR: mirror-common.sh not found" >&2
  exit 1
}

show_help() {
  grep '^#' "$0" | grep -E '^\s*#\s+(Usage|Options|  )' | sed 's/^#\s*//'
}

# Parse arguments
if ! parse_mirror_args "$@"; then
  show_help
  exit 1
fi

# Detect or use provided distro
DISTRO="${MIRROR_DISTRO:-$(detect_distro)}"
log_info "detected distro: $DISTRO"

# Ensure running as root for mirror operations
ensure_root "$@"

# Route to distro-specific mirror script
DISTRO_SCRIPT=""
case "$DISTRO" in
  arch|manjaro|artix)
    DISTRO_SCRIPT="$SCRIPT_DIR/arch.sh"
    ;;
  ubuntu|debian)
    DISTRO_SCRIPT="$SCRIPT_DIR/ubuntu.sh"
    ;;
  fedora)
    DISTRO_SCRIPT="$SCRIPT_DIR/fedora.sh"
    ;;
  gentoo)
    DISTRO_SCRIPT="$SCRIPT_DIR/gentoo.sh"
    ;;
  *)
    log_error "unsupported distro: $DISTRO (supported: arch, ubuntu, fedora, gentoo)"
    exit 1
    ;;
esac

if [ ! -x "$DISTRO_SCRIPT" ]; then
  log_error "distro script not found or not executable: $DISTRO_SCRIPT"
  exit 1
fi

log_info "invoking distro-specific mirror script: $DISTRO_SCRIPT"
exec "$DISTRO_SCRIPT"
