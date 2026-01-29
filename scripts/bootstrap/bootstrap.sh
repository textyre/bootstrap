#!/usr/bin/env bash
set -eu

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/bootstrap.log"
export LOG_FILE="$LOGFILE"
# Mark that bootstrap logging is active so child scripts don't re-enable it
export BOOTSTRAP_LOG_ACTIVE=1
# Duplicate all stdout/stderr to the log file (append). Keep ANSI colors.
exec > >(tee -a "$LOGFILE") 2>&1

source "$SCRIPT_DIR/../lib/log.sh" || true
: ${SCRIPT_NAME:=$(basename "$0")}
INSTALL_SCRIPT="$SCRIPT_DIR/packager/install.sh"
EXTERNALS_HELPER="$SCRIPT_DIR/externals/externals.sh"

# Parse arguments and set DO_INSTALL, EXTERNALS_ROOT
. "$SCRIPT_DIR/parse-args.sh"
parse_bootstrap_args "$@"

# Default DO_ANSIBLE if not set by parse-args.sh
: ${DO_ANSIBLE:=1}

log_info "Bootstrap started with: DO_INSTALL=$DO_INSTALL, DO_ANSIBLE=$DO_ANSIBLE, EXTERNALS_ROOT=${EXTERNALS_ROOT:-<host>}"

# ============================================================================
# VAULT PASSWORD: needed for Ansible become password decryption
# ============================================================================
VAULT_PASS_FILE="${HOME}/.vault-pass"
if [ "$DO_ANSIBLE" = 1 ] && [ ! -f "$VAULT_PASS_FILE" ]; then
  log_info "Vault password file not found at $VAULT_PASS_FILE"
  read -s -p "Enter Ansible vault password: " _vault_pass
  echo ""
  echo "$_vault_pass" > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
  unset _vault_pass
  log_info "Vault password saved to $VAULT_PASS_FILE (chmod 600)"
fi

# Validate all required scripts exist and are executable
if [ ! -x "$INSTALL_SCRIPT" ]; then
  log_error "installer script not found or not executable: $INSTALL_SCRIPT"
  exit 1
fi

if [ -n "${EXTERNALS_ROOT:-}" ] && [ ! -x "$EXTERNALS_HELPER" ]; then
  log_error "externals helper not found or not executable: $EXTERNALS_HELPER"
  exit 1
fi

# ============================================================================
# PHASE 0: EXTERNALS INITIALIZATION (always run if EXTERNALS_ROOT is set)
# ============================================================================
if [ -n "${EXTERNALS_ROOT:-}" ]; then
  log_info "Initializing externals root: $EXTERNALS_ROOT"
  log_info "Invoking externals helper: $EXTERNALS_HELPER"
  sudo "$EXTERNALS_HELPER" "$EXTERNALS_ROOT"
fi

# ============================================================================
# PHASE 1: INSTALL (mirror search + package installation)
# ============================================================================
if [ "$DO_INSTALL" = 1 ]; then
  log_info "Starting install phase (mirror search + package installation)"
  
  log_debug "Running mirror manager..."
  # Mirror manager options can be passed via MIRROR_* environment variables:
  # MIRROR_DISTRO, MIRROR_PROTOCOL, MIRROR_LATEST, MIRROR_AGE, 
  # MIRROR_SORT_BY, MIRROR_COUNTRY, MIRROR_VALIDATE, MIRROR_DEBUG
  "$SCRIPT_DIR/mirror/mirror-manager.sh" ${MIRROR_OPTS:-}
  
  log_info "Running package installer..."
  "$INSTALL_SCRIPT" "${EXTERNALS_ROOT:-}"
else
  log_warning "Install phase skipped. Ensure required packages are already installed."
fi

# ============================================================================
# PHASE 2: ANSIBLE WORKSTATION SETUP (packages + dotfiles + services)
# ============================================================================
if [ "$DO_ANSIBLE" = 1 ]; then
  log_info "Starting Ansible workstation setup"
  ANSIBLE_DIR="$SCRIPT_DIR/ansible"

  if [ ! -d "$ANSIBLE_DIR/.venv" ]; then
    log_info "Bootstrapping Ansible environment..."
    (cd "$ANSIBLE_DIR" && task bootstrap)
  fi

  log_info "Applying workstation playbook..."
  (cd "$ANSIBLE_DIR" && task workstation)
else
  log_info "Ansible phase skipped."
fi

log_info "Bootstrap completed successfully"

