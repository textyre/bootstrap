#!/bin/bash
# ============================================================
# Ewwii Launch Script — Floating Island Bars
# Terminates existing instances and launches fresh
# Dynamic sizing handled by listen() subscriptions
# ============================================================

set -euo pipefail

# Kill existing ewwii instances
ewwii kill 2>/dev/null || true
sleep 0.3

# Start daemon
ewwii daemon &
sleep 0.5

# Open all windows
# listen() scripts will automatically calculate sizes/positions
ewwii open workspaces
ewwii open workspace-add
ewwii open clock
ewwii open system

echo "Ewwii started successfully"
