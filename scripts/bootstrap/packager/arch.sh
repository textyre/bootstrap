#!/usr/bin/env bash
# arch.sh - packager functions for Arch Linux (pacman)

pm_update() {
  root=${1:-}
  if [ -n "$root" ]; then
    sudo mkdir -p "$root/var/lib/pacman/sync" "$root/var/cache/pacman/pkg"
    sudo pacman --root "$root" --dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" --config /etc/pacman.conf -Sy --noconfirm
  else
    sudo pacman -Sy --noconfirm
  fi
}

pm_install() {
  root=${1:-}
  shift || true
  if [ "$#" -eq 0 ]; then
    echo "pm_install (arch): no packages specified" >&2
    return 2
  fi
  if [ -n "$root" ]; then
    sudo mkdir -p "$root/var/lib/pacman/sync" "$root/var/cache/pacman/pkg"
    sudo pacman --root "$root" --dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" --config /etc/pacman.conf -S --needed --noconfirm "$@"
  else
    sudo pacman -S --needed --noconfirm "$@"
  fi
}

# Prepare an externals root for pacman operations. Creates expected
# pacman directories, initializes the keyring if missing, and mounts
# pseudo-filesystems (/proc, /sys, /dev, /run) for proper hook execution.
pm_prepare_root() {
  root=${1:-}
  if [ -z "$root" ]; then
    return 0
  fi
  
  # Create directories for pacman operations (will be owned by root by default)
  sudo mkdir -p "$root/var/lib/pacman/sync" "$root/var/cache/pacman/pkg" "$root/etc/pacman.d"
  
  # If the keyring isn't present, create a minimal one so pacman can verify
  # packages. This uses the host pacman-key binary to initialize/populate the
  # target keyring in a best-effort way.
  if [ ! -d "$root/etc/pacman.d/gnupg" ]; then
    sudo mkdir -p "$root/etc/pacman.d/gnupg"
    if command -v pacman-key >/dev/null 2>&1; then
      sudo pacman-key --gpgdir "$root/etc/pacman.d/gnupg" --init
      sudo pacman-key --gpgdir "$root/etc/pacman.d/gnupg" --populate archlinux
    fi
  fi
  
  # Mount pseudo-filesystems so hooks (ldconfig, update-icon-cache, etc.) work correctly
  echo "Mounting pseudo-filesystems for hook support..."
  sudo mkdir -p "$root/dev" "$root/proc" "$root/sys" "$root/run"
  sudo mount --bind /dev  "$root/dev" 2>/dev/null || true
  sudo mount -t proc proc "$root/proc" 2>/dev/null || true
  sudo mount -t sysfs sys "$root/sys" 2>/dev/null || true
  sudo mount --bind /run  "$root/run" 2>/dev/null || true
}

# Cleanup: unmount pseudo-filesystems from externals root.
# Call this after package operations are complete.
pm_cleanup_root() {
  root=${1:-}
  if [ -z "$root" ]; then
    return 0
  fi
  echo "Unmounting pseudo-filesystems..."
  sudo umount "$root/run" 2>/dev/null || true
  sudo umount "$root/sys" 2>/dev/null || true
  sudo umount "$root/proc" 2>/dev/null || true
  sudo umount "$root/dev" 2>/dev/null || true
  
  # Change ownership of all files to the target user
  local target_user="${SUDO_USER:-$USER}"
  echo "Changing ownership to $target_user..."
  sudo chown -R "$target_user:$target_user" "$root"
  
  # Restore original home directory permissions if they were changed
  if [ -f "$root/.perms_restore" ]; then
    source "$root/.perms_restore"
    if [ -n "${RESTORE_HOME_PERMS_FILE:-}" ] && [ -f "$RESTORE_HOME_PERMS_FILE" ]; then
      original_perms=$(cat "$RESTORE_HOME_PERMS_FILE")
      home_dir=$(echo "$root" | cut -d'/' -f1-3)
      echo "Restoring home directory permissions ($home_dir -> $original_perms)..."
      chmod "$original_perms" "$home_dir"
      rm -f "$RESTORE_HOME_PERMS_FILE" "$root/.perms_restore"
    fi
  fi
}

export -f pm_update pm_install pm_prepare_root pm_cleanup_root 2>/dev/null || true
