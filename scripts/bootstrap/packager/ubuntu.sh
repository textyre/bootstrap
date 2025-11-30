#!/usr/bin/env bash
# ubuntu.sh - packager functions for Ubuntu/Debian (apt)

pm_update() {
  root=${1:-}
  if [ -n "$root" ]; then
    # Attempt to run apt update inside chroot; assumes minimal layout exists.
    if command -v chroot >/dev/null 2>&1; then
      sudo chroot "$root" /bin/sh -c 'apt-get update -y' || echo "apt update in chroot failed" >&2
    else
      echo "chroot not available; cannot run apt update in root $root" >&2
    fi
  else
    sudo apt update -y || sudo apt-get update -y
  fi
}

pm_install() {
  root=${1:-}
  shift || true
  if [ "$#" -eq 0 ]; then
    echo "pm_install (ubuntu): no packages specified" >&2
    return 2
  fi
  if [ -n "$root" ]; then
    if command -v chroot >/dev/null 2>&1; then
      sudo chroot "$root" /bin/sh -c "apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y $*" || echo "apt install in chroot failed" >&2
    else
      echo "chroot not available; cannot install into $root" >&2
      return 3
    fi
  else
    sudo apt install -y "$@" || sudo apt-get install -y "$@"
  fi
}

export -f pm_update pm_install 2>/dev/null || true

# Prepare a Debian/Ubuntu chroot. For now this creates the root dir; using
# debootstrap is recommended for a fully-functional chroot and can be added
# here if desired.
pm_prepare_root() {
  root=${1:-}
  [ -n "$root" ] || return 0
  sudo mkdir -p "$root"
}

export -f pm_prepare_root 2>/dev/null || true
