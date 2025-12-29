#!/usr/bin/env bash
set -euo pipefail

# Install `yay` AUR helper.
# Usage:
#  - As normal user: ./scripts/bootstrap/yay
#  - To run non-interactively: sudo bash ./scripts/bootstrap/yay (the script will use $SUDO_USER for the build step)

SCRIPT_NAME=$(basename "$0")
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../../lib/log.sh"

if command -v yay >/dev/null 2>&1; then
    log_info "yay is already installed: $(command -v yay)"
    exit 0
fi

log_info "Ensuring required packages are installed via pacman..."
sudo pacman -S --needed --noconfirm base-devel git >/dev/null

# Determine user to run makepkg as
build_user=${SUDO_USER:-${USER:-$(whoami)}}

log_info "Building yay as user: $build_user"

build_dir=$(mktemp -d)
cleanup() {
    log_debug "Removing build dir: $build_dir"
    rm -rf "$build_dir" || log_warning "Failed to remove $build_dir"
}
trap 'cleanup' EXIT INT TERM

sudo -u "$build_user" bash -c "
  set -euo pipefail
  cd '$build_dir'
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
"

log_info "yay installation finished."

if command -v yay >/dev/null 2>&1; then
    log_info "yay location: $(command -v yay)"
else
    log_warning "yay not found in PATH after build. You may need to add /usr/bin to PATH or check the build logs."
    exit 1
fi

exit 0
