#!/usr/bin/env bash
set -euo pipefail

# Simple reflector module
# - ensures `reflector` is installed
# - backs up existing /etc/pacman.d/mirrorlist
# - generates a new mirrorlist using reflector
# Intended to be executed via sudo from the bootstrap flow.

log() { echo "[reflector] $*"; }

# If not running as root, re-exec this script under sudo so caller
# can simply invoke the script without wrapping it in sudo.
if [ "$(id -u)" -ne 0 ]; then
	log "re-executing with sudo..."
	exec sudo bash "$0" "$@"
fi

if ! command -v reflector >/dev/null 2>&1; then
	log "installing reflector..."
	pacman -Sy --noconfirm reflector
fi

MIRRORLIST=/etc/pacman.d/mirrorlist
BACKUP_DIR=/etc/pacman.d
BACKUP_FILE="$BACKUP_DIR/mirrorlist.bak.$(date +%Y%m%d%H%M%S)"

if [ -f "$MIRRORLIST" ]; then
	cp -p "$MIRRORLIST" "$BACKUP_FILE"
	log "existing mirrorlist backed up to $BACKUP_FILE"
fi

log "generating new mirrorlist (https, latest 5, age 12h, sort by rate)..."
reflector --verbose --protocol https --latest 5 --age 12 --sort rate --save "$MIRRORLIST"

log "refreshing pacman DB (double sync)"
pacman -Syy || true

log "reflector: done"
