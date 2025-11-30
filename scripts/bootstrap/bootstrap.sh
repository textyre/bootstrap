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
GUI_LAUNCHER="$SCRIPT_DIR/gui/launch.sh"
CHECK_PYTHON_SCRIPT="$SCRIPT_DIR/check-python.sh"

# Parse arguments and set DO_INSTALL, DO_DEPLOY, EXTERNALS_ROOT
. "$SCRIPT_DIR/parse-args.sh"
parse_bootstrap_args "$@"

log_info "Bootstrap started with: DO_INSTALL=$DO_INSTALL, DO_DEPLOY=$DO_DEPLOY, EXTERNALS_ROOT=${EXTERNALS_ROOT:-<host>}"

# Validate all required scripts exist and are executable
if [ ! -x "$INSTALL_SCRIPT" ]; then
  log_error "installer script not found or not executable: $INSTALL_SCRIPT"
  exit 1
fi

if [ ! -x "$GUI_LAUNCHER" ]; then
  log_error "GUI launcher not found or not executable: $GUI_LAUNCHER"
  exit 1
fi

if [ ! -x "$CHECK_PYTHON_SCRIPT" ]; then
  log_error "Python checker not found or not executable: $CHECK_PYTHON_SCRIPT"
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
  if [ "$DO_DEPLOY" = 1 ]; then
    log_warning "Deploy phase requires packages to be present. If missing, deploy may fail."
  fi
fi

# ============================================================================
# PHASE 2: DEPLOY (environment configuration)
# ============================================================================
if [ "$DO_DEPLOY" = 1 ]; then
  log_info "Starting deploy phase (environment configuration)"
  
  # Check Python availability before deploy
  log_info "Checking Python 3 availability (required for deploy)..."
  . "$CHECK_PYTHON_SCRIPT"
  
  if ! check_python_deployable; then
    log_error "Deploy phase requires Python 3. Install with: sudo pacman -S python"
    exit 1
  fi
  
  log_info "Configuring environment via $GUI_LAUNCHER"
  "$GUI_LAUNCHER"
else
  log_info "Deploy phase skipped. Environment configuration not performed."
fi

log_info "Bootstrap completed successfully"

