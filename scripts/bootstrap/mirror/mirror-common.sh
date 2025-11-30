#!/usr/bin/env bash
set -euo pipefail

# mirror-common.sh
# Common functions and utilities for mirror selection across all distros.
# Sourced by mirror-manager.sh and distro-specific scripts.

# Logging helper
log_info() { echo "[mirror] INFO: $*"; }
log_warn() { echo "[mirror] WARN: $*" >&2; }
log_error() { echo "[mirror] ERROR: $*" >&2; }
log_debug() { 
  if [ "${MIRROR_DEBUG:-0}" = "1" ]; then
    echo "[mirror] DEBUG: $*" >&2
  fi
}

# Re-execute with sudo if not running as root
ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_info "re-executing with sudo..."
    exec sudo bash "$0" "$@"
  fi
}

# Determine the current distro from /etc/os-release
detect_distro() {
  if [ -n "${MIRROR_DISTRO:-}" ]; then
    echo "$MIRROR_DISTRO"
    return 0
  fi
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown}"
    return 0
  fi
  
  log_error "Cannot detect distro: /etc/os-release not found"
  return 1
}

# Create a timestamped backup
backup_file() {
  local file=$1
  if [ -f "$file" ]; then
    local backup="$file.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$file" "$backup"
    log_info "backed up: $file -> $backup"
    echo "$backup"
  fi
}

# Restore file from backup
restore_from_backup() {
  local backup=$1
  if [ -f "$backup" ]; then
    local original="${backup%.bak.*}"
    cp -p "$backup" "$original"
    log_info "restored: $backup -> $original"
    return 0
  fi
  return 1
}

# Check if a command exists
has_command() {
  command -v "$1" >/dev/null 2>&1
}

# Install a package using the distro's package manager
install_package() {
  local pkg=$1
  local distro="${MIRROR_DISTRO:-$(detect_distro)}"
  
  case "$distro" in
    arch|manjaro|artix)
      sudo pacman -Sy --noconfirm "$pkg" || return 1
      ;;
    ubuntu|debian)
      sudo apt update -y && sudo apt install -y "$pkg" || return 1
      ;;
    fedora)
      sudo dnf install -y "$pkg" || return 1
      ;;
    gentoo)
      sudo emerge --ask=n "$pkg" || return 1
      ;;
    *)
      log_error "unsupported distro for package installation: $distro"
      return 1
      ;;
  esac
}

# Validate that a URL is accessible
validate_mirror() {
  local url=$1
  if has_command curl; then
    curl -s --connect-timeout 5 -m 10 -I "$url" >/dev/null 2>&1 && return 0
  elif has_command wget; then
    wget --connect-timeout=5 --timeout=10 -q --spider "$url" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Convert country code to country name (simple mapping)
# Supported countries: KZ, RU, DE, FR, NL
country_name_from_code() {
  local code=$1
  case "$code" in
    KZ) echo "Kazakhstan" ;;
    RU) echo "Russia" ;;
    DE) echo "Germany" ;;
    FR) echo "France" ;;
    NL) echo "Netherlands" ;;
    *) echo "$code" ;;
  esac
}

# Parse common CLI arguments
parse_mirror_args() {
  local distro="" protocol="https" latest=5 age=12 sort_by="rate" country="KZ" validate=0
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --distro)
        distro="$2"
        shift 2
        ;;
      --protocol)
        protocol="$2"
        shift 2
        ;;
      --latest)
        latest="$2"
        shift 2
        ;;
      --age)
        age="$2"
        shift 2
        ;;
      --sort-by)
        sort_by="$2"
        shift 2
        ;;
      --country)
        country="$2"
        shift 2
        ;;
      --validate)
        validate=1
        shift
        ;;
      --debug)
        MIRROR_DEBUG=1
        shift
        ;;
      -h|--help)
        return 1
        ;;
      *)
        log_error "unknown argument: $1"
        return 1
        ;;
    esac
  done
  
  # Export parsed values for use in caller (KZ is default country)
  export MIRROR_PROTOCOL="$protocol"
  export MIRROR_LATEST="$latest"
  export MIRROR_AGE="$age"
  export MIRROR_SORT_BY="$sort_by"
  export MIRROR_COUNTRY="${country:-KZ}"
  export MIRROR_VALIDATE="$validate"
  export MIRROR_DISTRO="$distro"
  
  return 0
}

# Export functions for subshells
export -f log_info log_warn log_error log_debug
export -f ensure_root detect_distro backup_file restore_from_backup
export -f has_command install_package validate_mirror
export -f country_name_from_code parse_mirror_args
