#!/usr/bin/env bash
# check-python.sh - Python availability verification for bootstrap deploy phase
# Usage: source this file, then call check_python_available or check_python_deployable

# check_python_available - Verify python3 binary exists and is executable
# Returns: 0 if python3 is available, 1 if not
check_python_available() {
  if command -v python3 &> /dev/null; then
    log_info "Python 3 is available: $(python3 --version)"
    return 0
  else
    log_error "Python 3 is required for deploy phase but not found"
    log_error "Please install python3 package or use --install flag to include it"
    return 1
  fi
}

# check_python_deployable - Verify python3 can execute required modules
# This checks that Python can be used for GUI/deploy operations
# Returns: 0 if python3 is suitable for deploy, 1 if not
check_python_deployable() {
  if ! check_python_available; then
    return 1
  fi
  
  # Verify Python can import sys (basic functionality check)
  if python3 -c "import sys" 2>/dev/null; then
    log_debug "Python 3 is suitable for deploy operations"
    return 0
  else
    log_error "Python 3 found but unable to run deploy modules"
    return 1
  fi
}
