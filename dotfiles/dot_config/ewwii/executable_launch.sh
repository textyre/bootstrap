#!/bin/bash
# ============================================================
# Ewwii Launch Script — Floating Island Bars
# Terminates existing instances and launches fresh
# Dynamic sizing handled by listen() subscriptions
# ============================================================

set -euo pipefail

# Ensure DISPLAY is set for X11 (needed when launched via SSH or autostart)
export DISPLAY="${DISPLAY:-:0}"

# Use Cairo renderer to reduce RAM usage (~200MB -> ~30MB)
export GSK_RENDERER=cairo

# Kill existing ewwii instances
ewwii kill 2>/dev/null || true
sleep 0.3

# Start daemon
ewwii daemon &
sleep 0.5

# Opens the bar window with floating islands
ewwii open bar

echo "Ewwii started successfully"
