#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found. Install shellcheck to run linting (e.g. sudo pacman -S shellcheck)." >&2
  exit 2
fi

echo "Running shellcheck on scripts/ ..."
shellcheck -x -S info "$ROOT/../scripts"/*.sh || true
shellcheck -x -S info -r "$(find "$ROOT/../scripts" -type f -name '*.sh' -print)" || true

echo "Done. Review shellcheck output above (exit code 0 indicates success)."
