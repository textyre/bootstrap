#!/usr/bin/env bash
# parse-args.sh - argument parsing for bootstrap scripts
# Usage: source this file, then call parse_bootstrap_args "$@"
# After calling, EXTERNALS_ROOT, DO_INSTALL, and DO_DEPLOY will be set appropriately.

parse_bootstrap_args() {
  # By default do not use externals; install on host unless user passes --externals
  EXTERNALS_ROOT=""
  # Mode flags: by default, both install and deploy are disabled
  # If neither flag is provided, both will be enabled
  DO_INSTALL=0
  DO_DEPLOY=0
  
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --install)
        DO_INSTALL=1
        shift
        ;;
      --deploy)
        DO_DEPLOY=1
        shift
        ;;
      --externals)
        shift
        if [ -z "${1:-}" ]; then
          echo "--externals requires a path" >&2
          return 2
        fi
        EXTERNALS_ROOT="$1"
        shift
        ;;
      --no-externals)
        EXTERNALS_ROOT=""
        shift
        ;;
      --help|-h)
        show_bootstrap_usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        show_bootstrap_usage
        return 2
        ;;
    esac
  done
  
  # If neither mode flag was provided, enable both (default behavior)
  if [ "$DO_INSTALL" = 0 ] && [ "$DO_DEPLOY" = 0 ]; then
    DO_INSTALL=1
    DO_DEPLOY=1
  fi
  
  # Export variables for use in child scripts
  export DO_INSTALL
  export DO_DEPLOY
  export EXTERNALS_ROOT
}

show_bootstrap_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --install          Run only the install phase (mirror search + packages)
  --deploy           Run only the deploy phase (environment configuration)
  --externals PATH   Configure externals root to PATH (works with both phases)
  --no-externals     Install directly on host (do not set EXTERNALS_ROOT)
  --help             Show this help

Modes (can be combined in any order):
  (no flags)         Run both install and deploy phases (default)
  --install          Run only mirror search and package installation
  --deploy           Run only environment configuration (requires Python 3)
  --install --deploy Explicitly run both phases

Examples:
  $0                              # Install packages, then configure environment
  $0 --install                    # Only install packages and find mirrors
  $0 --deploy                     # Only configure environment (must have packages)
  $0 --install --externals /opt   # Install to /opt, then configure environment
  $0 --deploy --externals /opt    # Configure environment in /opt
EOF
}
