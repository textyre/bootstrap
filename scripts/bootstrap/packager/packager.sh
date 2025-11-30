#!/usr/bin/env bash
set -eu

# packager.sh
# Sourcing entrypoint for distro-specific package operations.
# Usage (sourced): source packager/packager.sh [distro]
# After sourcing this file, the functions `pm_update [root]` and
# `pm_install [root] pkg...` will be available in the current shell.

PACKAGER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)

# Determine distro: env PACKAGER_DISTRO, or /etc/os-release
if [ -n "${PACKAGER_DISTRO:-}" ]; then
  DISTRO="$PACKAGER_DISTRO"
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO="${ID:-unknown}"
else
  DISTRO="unknown"
fi

case "$DISTRO" in
  arch|manjaro|artix)
    . "$PACKAGER_DIR/arch.sh"
    ;;
  ubuntu|debian)
    . "$PACKAGER_DIR/ubuntu.sh"
    ;;
  fedora)
    . "$PACKAGER_DIR/fedora.sh"
    ;;
  gentoo)
    . "$PACKAGER_DIR/gentoo.sh"
    ;;
  *)
    echo "packager: unsupported or unknown distro '$DISTRO' — supported: arch, ubuntu, fedora, gentoo" >&2
    return 2 2>/dev/null || exit 2
    ;;
esac

# After sourcing a distro script, pm_update and pm_install should be defined.
if ! command -v pm_update >/dev/null 2>&1 || ! command -v pm_install >/dev/null 2>&1; then
  echo "packager: distro script did not provide pm_update/pm_install functions" >&2
  return 3 2>/dev/null || exit 3
fi

# If an externals root is configured, allow the distro script to prepare it
# (create package-manager-specific layout, init keyring, etc.). The
# distro script may optionally define `pm_prepare_root <root>`; if present
# and EXTERNALS_ROOT is set, invoke it now.
if [ -n "${EXTERNALS_ROOT:-}" ]; then
  if command -v pm_prepare_root >/dev/null 2>&1; then
    pm_prepare_root "${EXTERNALS_ROOT}"
  fi
fi

# If packager.sh is executed (not sourced), offer a simple CLI wrapping
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # CLI: packager.sh <action> [root] [packages...]
  action=${1:-update}
  root=${2:-}
  shift 2 || true
  case "$action" in
    update)
      pm_update "$root"
      ;;
    install)
      pm_install "$root" "$@"
      ;;
    *)
      echo "Usage: $0 [update|install] [root] [packages...]" >&2
      exit 2
      ;;
  esac
fi
