#!/usr/bin/env bash
# fedora.sh - packager functions for Fedora (dnf)

pm_update() {
  root=${1:-}
  if [ -n "$root" ]; then
    sudo dnf --installroot="$root" -y makecache || sudo dnf --installroot="$root" -y check-update
  else
    sudo dnf -y makecache
  fi
}

pm_install() {
  root=${1:-}
  shift || true
  if [ "$#" -eq 0 ]; then
    echo "pm_install (fedora): no packages specified" >&2
    return 2
  fi
  if [ -n "$root" ]; then
    sudo dnf --installroot="$root" -y install "$@"
  else
    sudo dnf -y install "$@"
  fi
}

export -f pm_update pm_install 2>/dev/null || true

# Optional: prepare a target root for dnf. By default do nothing; if you need
# repository metadata or minimal layout, implement here.
pm_prepare_root() {
  root=${1:-}
  [ -n "$root" ] || return 0
  sudo mkdir -p "$root"
}

export -f pm_prepare_root 2>/dev/null || true
