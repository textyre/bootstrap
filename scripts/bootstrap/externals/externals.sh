#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 /path/to/externals

This prepares an externals root for pacman operations by creating
expected directories and setting permissive ownership/permissions so
pacman (and its DownloadUser, typically 'alpm') can write to them.

Example:
  sudo ./externals.sh /home/youruser/externals
EOF
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

ROOT=$1

echo "Preparing externals root: $ROOT"

sudo mkdir -p "$ROOT"

# Create expected pacman directories
sudo mkdir -p "$ROOT/var/lib/pacman/sync"
sudo mkdir -p "$ROOT/var/cache/pacman/pkg"
sudo mkdir -p "$ROOT/etc/pacman.d"
# Do not modify parent or home directories; only operate inside EXTERNALS_ROOT.

# If the alpm user exists, make pacman dirs writable by that group
if id -u alpm >/dev/null 2>&1; then
  echo "Found user/group 'alpm' — setting group ownership and group-write perms"
  sudo chown -R root:alpm "$ROOT/var" "$ROOT/etc"
  sudo chmod -R 2775 "$ROOT/var" "$ROOT/etc"
else
  echo "User 'alpm' not found — falling back to root ownership and 755 perms"
  sudo chown -R root:root "$ROOT/var" "$ROOT/etc"
  sudo chmod -R 755 "$ROOT/var" "$ROOT/etc"
fi

echo "Prepared $ROOT"
