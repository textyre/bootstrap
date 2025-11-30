#!/usr/bin/env bash
# gentoo.sh - packager functions for Gentoo (emerge/portage)

pm_update() {
  root=${1:-}
  if [ -n "$root" ]; then
    if command -v emerge >/dev/null 2>&1; then
      sudo emerge --root="$root" --sync || echo "emerge --sync in root may require a configured Portage tree" >&2
    else
      echo "emerge not found on host; cannot update Gentoo tree in $root" >&2
    fi
  else
    sudo emerge --sync || echo "emerge --sync failed" >&2
  fi
}

pm_install() {
  root=${1:-}
  shift || true
  if [ "$#" -eq 0 ]; then
    echo "pm_install (gentoo): no packages specified" >&2
    return 2
  fi
  if [ -n "$root" ]; then
    if command -v emerge >/dev/null 2>&1; then
      sudo emerge --root="$root" "$@"
    else
      echo "emerge not found on host; cannot install into $root" >&2
      return 3
    fi
  else
    sudo emerge "$@"
  fi
}

export -f pm_update pm_install 2>/dev/null || true

# Prepare a gentoo root (best-effort). Real Gentoo chroots usually require
# configuring /etc/portage and a Portage tree in the target; here we create
# the target directory only.
pm_prepare_root() {
  root=${1:-}
  [ -n "$root" ] || return 0
  sudo mkdir -p "$root"
}

export -f pm_prepare_root 2>/dev/null || true
