#!/usr/bin/env bash
# Simple logging helper for shell scripts
# Usage: source scripts/lib/log.sh; log_info "message"

: "${LOG_LEVEL:=INFO}"
: "${LOG_FILE:=}
"

# map level name to numeric priority
_log_level_num() {
    case "$1" in
        DEBUG) echo 10 ;;
        INFO) echo 20 ;;
        WARNING) echo 30 ;;
        ERROR) echo 40 ;;
        CRITICAL) echo 50 ;;
        *) echo 20 ;;
    esac
}

# color codes for levels
_DEBUG="\e[36m"
_INFO="\e[32m"
_WARNING="\e[33m"
_ERROR="\e[31m"
_CRITICAL="\e[41m"
_RESET="\e[0m"

_log_emit() {
    local level="$1"; shift
    local msg="$*"
    local levelnum=$( _log_level_num "$level" )
    local curlevelnum=$( _log_level_num "$LOG_LEVEL" )

    if [ "$levelnum" -lt "$curlevelnum" ]; then
        return 0
    fi

    local color=""
    case "$level" in
        DEBUG) color="$_DEBUG" ;;
        INFO) color="$_INFO" ;;
        WARNING) color="$_WARNING" ;;
        ERROR) color="$_ERROR" ;;
        CRITICAL) color="$_CRITICAL" ;;
    esac

    # Console: colorize only the level token
    printf '%b' "[${color}${level}${_RESET}] ${SCRIPT_NAME}: ${msg}\n"

    # If LOG_FILE set, append plain text (no colors)
    if [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        printf '[%s] %s: %s\n' "$level" "$SCRIPT_NAME" "$msg" >> "$LOG_FILE"
    fi
}

log_debug()    { _log_emit DEBUG "$*"; }
log_info()     { _log_emit INFO "$*"; }
log_warning()  { _log_emit WARNING "$*"; }
log_error()    { _log_emit ERROR "$*"; }
log_critical() { _log_emit CRITICAL "$*"; }
