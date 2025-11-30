#!/usr/bin/env bash
set -euo pipefail

# mirror/gentoo.sh
# Gentoo mirror selection via Portage configuration.
# Supports country-based selection and mirror validation.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/mirror-common.sh" || exit 1

log_info "configuring Gentoo mirrors"

# Gentoo mirrors for supported countries
# Supported countries: KZ, RU, DE, FR, NL
declare -A COUNTRY_MIRRORS=(
  [KZ]="https://mirror.rol.ru/gentoo"
  [RU]="https://mirror.rol.ru/gentoo"
  [DE]="https://mirror.eu.oneandone.net/linux/gentoo"
  [FR]="https://mirror.switch.ch/mirror/gentoo"
  [NL]="https://gentoo.osuosl.org"
)

# Fallback mirrors
declare -a FALLBACK_MIRRORS=(
  "https://gentoo.osuosl.org"
  "https://mirror.eu.oneandone.net/linux/gentoo"
  "https://mirror.switch.ch/mirror/gentoo"
)

# Select primary mirror
PRIMARY_MIRROR="https://gentoo.osuosl.org"
if [ -n "${MIRROR_COUNTRY:-}" ] && [ -n "${COUNTRY_MIRRORS[${MIRROR_COUNTRY}]:-}" ]; then
  PRIMARY_MIRROR="${COUNTRY_MIRRORS[$MIRROR_COUNTRY]}"
  log_info "selected mirror for country ${MIRROR_COUNTRY}: $PRIMARY_MIRROR"
fi

# Test mirror accessibility if validation is enabled
if [ "${MIRROR_VALIDATE:-0}" = "1" ]; then
  log_info "validating mirror accessibility..."
  TEST_URL="${PRIMARY_MIRROR}/distfiles/"
  
  if validate_mirror "$TEST_URL"; then
    log_info "mirror validation successful: $PRIMARY_MIRROR"
  else
    log_warn "mirror validation failed for $PRIMARY_MIRROR, trying fallback mirrors..."
    
    # Try fallback mirrors
    for mirror in "${FALLBACK_MIRRORS[@]}"; do
      if [ "$mirror" != "$PRIMARY_MIRROR" ]; then
        TEST_URL="${mirror}/distfiles/"
        if validate_mirror "$TEST_URL"; then
          PRIMARY_MIRROR="$mirror"
          log_info "using fallback mirror: $PRIMARY_MIRROR"
          break
        fi
      fi
    done
  fi
fi

# Portage configuration directory
PORTAGE_DIR="/etc/portage"
MAKE_CONF="$PORTAGE_DIR/make.conf"

# Ensure portage directory exists
sudo mkdir -p "$PORTAGE_DIR"

# Backup current make.conf
if [ -f "$MAKE_CONF" ]; then
  BACKUP_FILE=$(backup_file "$MAKE_CONF")
fi

log_info "updating Portage make.conf with mirror: $PRIMARY_MIRROR"

# Update or create make.conf with mirror configuration
# Use a temporary file and then move it to ensure atomic update
TEMP_MAKE_CONF=$(mktemp)

if [ -f "$MAKE_CONF" ]; then
  # Remove any existing GENTOO_MIRRORS lines and preserve the rest
  grep -v "^GENTOO_MIRRORS=" "$MAKE_CONF" > "$TEMP_MAKE_CONF" || true
else
  # Create new file with comments
  cat > "$TEMP_MAKE_CONF" << 'EOF'
# Gentoo make.conf
# Automatically configured by mirror-manager

EOF
fi

# Append mirror configuration
cat >> "$TEMP_MAKE_CONF" << EOF

# Gentoo mirror configuration (auto-updated by mirror-manager)
GENTOO_MIRRORS="$PRIMARY_MIRROR"
EOF

# Move temporary file to make.conf
sudo mv "$TEMP_MAKE_CONF" "$MAKE_CONF"
sudo chmod 644 "$MAKE_CONF"

log_info "make.conf updated successfully"

# Sync Portage tree
log_info "syncing Portage tree..."
if emerge --sync 2>&1 | tail -20; then
  log_info "portage tree synced successfully"
else
  log_warn "portage tree sync had issues (this is expected if running for first time)"
fi

log_info "gentoo mirror selection complete"
