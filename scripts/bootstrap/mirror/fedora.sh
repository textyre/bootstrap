#!/usr/bin/env bash
set -euo pipefail

# mirror/fedora.sh
# Fedora mirror selection via dnf repo configuration.
# Supports country-based selection and mirror validation.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/mirror-common.sh" || exit 1

# Detect Fedora release
if [ -f /etc/os-release ]; then
  . /etc/os-release
  RELEASE_VERSION="${VERSION_ID:-39}"
else
  RELEASE_VERSION="39"
fi

log_info "detected Fedora version: $RELEASE_VERSION"

# Fedora mirrors for supported countries
# Supported countries: KZ, RU, DE, FR, NL
declare -a FEDORA_MIRRORS=(
  "download.fedoraproject.org"
  "mirror.de.example.com"
  "mirror.fr.example.com"
  "mirror.ru.example.com"
)

# Country to mirror mapping
declare -A COUNTRY_MIRRORS=(
  [KZ]="mirror.ru.example.com"
  [RU]="mirror.ru.example.com"
  [DE]="mirror.de.example.com"
  [FR]="mirror.fr.example.com"
  [NL]="download.fedoraproject.org"
)

# Select primary mirror
PRIMARY_MIRROR="download.fedoraproject.org"
if [ -n "${MIRROR_COUNTRY:-}" ] && [ -n "${COUNTRY_MIRRORS[${MIRROR_COUNTRY}]:-}" ]; then
  PRIMARY_MIRROR="${COUNTRY_MIRRORS[$MIRROR_COUNTRY]}"
  log_info "selected mirror for country ${MIRROR_COUNTRY}: $PRIMARY_MIRROR"
fi

# Test mirror accessibility if validation is enabled
if [ "${MIRROR_VALIDATE:-0}" = "1" ]; then
  log_info "validating mirror accessibility..."
  PROTOCOL="${MIRROR_PROTOCOL:-https}"
  TEST_URL="${PROTOCOL}://${PRIMARY_MIRROR}/fedora/releases/${RELEASE_VERSION}/Everything/x86_64/"
  
  if validate_mirror "$TEST_URL"; then
    log_info "mirror validation successful: $PRIMARY_MIRROR"
  else
    log_warn "mirror validation failed for $PRIMARY_MIRROR, using default"
    PRIMARY_MIRROR="download.fedoraproject.org"
  fi
fi

# Backup current fedora repo configs
REPO_DIR="/etc/yum.repos.d"
FEDORA_REPO="$REPO_DIR/fedora.repo"
UPDATES_REPO="$REPO_DIR/fedora-updates.repo"

if [ -f "$FEDORA_REPO" ]; then
  backup_file "$FEDORA_REPO"
fi

if [ -f "$UPDATES_REPO" ]; then
  backup_file "$UPDATES_REPO"
fi

# Generate repository configuration with selected mirror
log_info "generating fedora repository configuration with mirror: $PRIMARY_MIRROR"
PROTOCOL="${MIRROR_PROTOCOL:-https}"

# Create fedora.repo with selected mirror
cat > "$FEDORA_REPO" << EOF
[fedora]
name=Fedora \$releasever - \$basearch
baseurl=${PROTOCOL}://${PRIMARY_MIRROR}/fedora/releases/\$releasever/Everything/\$basearch/os/
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch
enabled=1
metadata_expire=7d
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[fedora-debuginfo]
name=Fedora \$releasever - \$basearch - Debug
baseurl=${PROTOCOL}://${PRIMARY_MIRROR}/fedora/releases/\$releasever/Everything/\$basearch/debug/
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=fedora-debug-\$releasever&arch=\$basearch
enabled=0
metadata_expire=7d
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[fedora-source]
name=Fedora \$releasever - Source
baseurl=${PROTOCOL}://${PRIMARY_MIRROR}/fedora/releases/\$releasever/Everything/source/tree/
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=fedora-source-\$releasever&arch=\$basearch
enabled=0
metadata_expire=7d
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF

# Create fedora-updates.repo
cat > "$UPDATES_REPO" << EOF
[updates]
name=Fedora \$releasever - \$basearch - Updates
baseurl=${PROTOCOL}://${PRIMARY_MIRROR}/fedora/updates/\$releasever/Everything/\$basearch/
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f\$releasever&arch=\$basearch
enabled=1
metadata_expire=6h
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[updates-testing]
name=Fedora \$releasever - \$basearch - Test Updates
baseurl=${PROTOCOL}://${PRIMARY_MIRROR}/fedora/updates/testing/\$releasever/Everything/\$basearch/
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=updates-testing-f\$releasever&arch=\$basearch
enabled=0
metadata_expire=6h
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[updates-testing-debuginfo]
name=Fedora \$releasever - \$basearch - Test Updates Debug
baseurl=${PROTOCOL}://${PRIMARY_MIRROR}/fedora/updates/testing/\$releasever/Everything/\$basearch/debug/
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=updates-testing-debug-f\$releasever&arch=\$basearch
enabled=0
metadata_expire=6h
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF

log_info "repository configuration updated successfully"

# Refresh package cache
log_info "refreshing package cache..."
if dnf makecache -y 2>&1; then
  log_info "package cache refreshed successfully"
else
  log_warn "package cache refresh had issues"
fi

log_info "fedora mirror selection complete"
