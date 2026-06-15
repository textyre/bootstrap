#!/usr/bin/env bash
# Validate that AUR packages don't provide packages already in the official list
# unless they are listed in CONFLICT_EXCEPTIONS.
#
# Environment variables (newline-separated):
#   AUR_PACKAGES        — AUR package names to check
#   OFFICIAL_PACKAGES   — official repo package names
#   CONFLICT_EXCEPTIONS — packages allowed to conflict (will be removed before AUR install)
set -euo pipefail

rc=0
for pkg in $AUR_PACKAGES; do
  yay_info=""
  yay_error=$(mktemp)
  for attempt in 1 2 3 4 5; do
    if yay_info=$(yay -Si "$pkg" 2>"$yay_error"); then
      break
    fi

    if [ "$attempt" -eq 5 ]; then
      echo "ERROR: unable to query AUR metadata for '$pkg' after $attempt attempts" >&2
      cat "$yay_error" >&2
      rm -f "$yay_error"
      exit 1
    fi

    sleep 10
  done
  rm -f "$yay_error"

  provides=$(printf '%s\n' "$yay_info" | awk '/^Provides/{$1=""; gsub(/[>=<][^ ]*/, ""); print}')
  for p in $provides; do
    [ -z "$p" ] && continue
    if echo "$OFFICIAL_PACKAGES" | grep -qxF "$p" && ! echo "$CONFLICT_EXCEPTIONS" | grep -qxF "$p"; then
      echo "CONFLICT: AUR '$pkg' provides '$p' — add to packages_aur_remove_conflicts"
      rc=1
    fi
  done
done

exit $rc
