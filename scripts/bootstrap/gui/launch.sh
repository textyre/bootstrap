#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# bootstrap directory (scripts/bootstrap)
BOOTSTRAP_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# scripts directory (parent of bootstrap) — this is the package root we want
SCRIPTS_DIR=$(cd "$BOOTSTRAP_DIR/.." && pwd)
LOG_DIR="$BOOTSTRAP_DIR/log"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/launch.log"
export LOG_FILE="$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# shell logging helper
source "$SCRIPTS_DIR/lib/log.sh" || true
: ${SCRIPT_NAME:=$(basename "$0")}

log_info "Starting Python GUI launcher module"

# Prefer exposing the `scripts` directory on PYTHONPATH so the package
# name `bootstrap` can be used (python -m bootstrap.gui.launch). This
# works whether you deploy the whole repo or only the `scripts/` folder.
export PYTHONPATH="${SCRIPTS_DIR}:${PYTHONPATH:-}"

exec python3 -m bootstrap.gui.launch "$@"
