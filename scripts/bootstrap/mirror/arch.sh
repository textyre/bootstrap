#!/usr/bin/env bash
set -euo pipefail

# mirror/arch.sh
# Arch Linux (pacman) mirror selection via reflector with dynamic parameters.
# Sourced variables from mirror-common.sh:
#   MIRROR_PROTOCOL, MIRROR_LATEST, MIRROR_AGE, MIRROR_SORT_BY,
#   MIRROR_COUNTRY, MIRROR_VALIDATE, MIRROR_DEBUG

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/mirror-common.sh" || exit 1

# Install reflector if missing
if ! has_command reflector; then
  log_info "reflector not found, installing..."
  install_package reflector || {
    log_error "failed to install reflector"
    exit 1
  }
fi

MIRRORLIST=/etc/pacman.d/mirrorlist
BACKUP_DIR=/etc/pacman.d
BACKUP_FILE=$(backup_file "$MIRRORLIST")

# Build reflector command with parsed parameters
REFLECTOR_ARGS=(
  "--verbose"
  "--protocol" "${MIRROR_PROTOCOL:-https}"
  "--latest" "${MIRROR_LATEST:-5}"
  "--age" "${MIRROR_AGE:-12}"
  "--sort" "${MIRROR_SORT_BY:-rate}"
)

# Add country filter if specified and supported by reflector
# Supported countries: RU, DE, FR, and others that reflector knows
# KZ (Kazakhstan) is NOT supported by reflector - will use RU mirrors instead
if [ -n "${MIRROR_COUNTRY:-}" ]; then
  COUNTRY_NAME=$(country_name_from_code "$MIRROR_COUNTRY")
  
  # Map unsupported countries to alternatives or skip country filter
  case "$MIRROR_COUNTRY" in
    KZ)
      # Kazakhstan not in reflector - use Russian mirrors instead
      log_info "Kazakhstan not directly supported by reflector, using Russian mirrors"
      REFLECTOR_ARGS+=("--country" "RU")
      ;;
    RU|DE|FR|NL|US|JP|CN|AU|BR|IN|*)
      # Try the country code as-is
      log_info "filtering mirrors by country: $COUNTRY_NAME"
      REFLECTOR_ARGS+=("--country" "$MIRROR_COUNTRY")
      ;;
  esac
fi

# Add mirror validation if requested
if [ "${MIRROR_VALIDATE:-0}" = "1" ]; then
  REFLECTOR_ARGS+=("--verify" "3")
  log_info "enabling mirror verification (3 retries)"
fi

REFLECTOR_ARGS+=("--save" "$MIRRORLIST")

log_info "generating mirrorlist with reflector..."
log_debug "reflector args: ${REFLECTOR_ARGS[*]}"

if reflector "${REFLECTOR_ARGS[@]}"; then
  log_info "mirrorlist generated successfully"
else
  log_warn "reflector failed with primary parameters, attempting fallback..."
  
  # Fallback: increase age, remove country filter
  FALLBACK_ARGS=(
    "--verbose"
    "--protocol" "${MIRROR_PROTOCOL:-https}"
    "--latest" "$((MIRROR_LATEST + 5))"
    "--age" "$((MIRROR_AGE * 2))"
    "--sort" "${MIRROR_SORT_BY:-rate}"
    "--save" "$MIRRORLIST"
  )
  
  log_debug "fallback reflector args: ${FALLBACK_ARGS[*]}"
  
  if reflector "${FALLBACK_ARGS[@]}"; then
    log_info "mirrorlist generated with fallback parameters"
  else
    log_warn "reflector failed with fallback parameters, trying aggressive fallback..."
    
    # Aggressive fallback: use all mirrors, no country filter, very loose age
    AGGRESSIVE_FALLBACK_ARGS=(
      "--verbose"
      "--protocol" "https"
      "--latest" "50"
      "--age" "48"
      "--sort" "rate"
      "--save" "$MIRRORLIST"
    )
    
    log_debug "aggressive fallback reflector args: ${AGGRESSIVE_FALLBACK_ARGS[*]}"
    
    if reflector "${AGGRESSIVE_FALLBACK_ARGS[@]}"; then
      log_info "mirrorlist generated with aggressive fallback parameters"
    else
      log_error "reflector failed even with aggressive fallback parameters"
      
      # Restore backup if available
      if [ -n "$BACKUP_FILE" ]; then
        log_warn "restoring previous mirrorlist from backup"
        restore_from_backup "$BACKUP_FILE"
      fi
      exit 1
    fi
  fi
fi

log_info "refreshing pacman database..."
if pacman -Syy; then
  log_info "pacman database refreshed successfully"
else
  log_warn "pacman database refresh had issues (may be network-related)"
fi

log_info "arch mirror selection complete"
