#!/usr/bin/env bash

set -euo pipefail

WS_NUM="$1"
ICONS_FILE="$HOME/.config/polybar/workspace-icons.conf"

# Layout constants (must match launch.sh)
GAPS_OUTER=8
EDGE_PADDING=8
GAP=18
ICON_WIDTH=16
MIN_WS=3

# Move all windows from this workspace to workspace 1
i3-msg "[workspace=$WS_NUM] move to workspace 1" >/dev/null 2>&1 || true

# Switch to workspace 1
i3-msg "workspace 1" >/dev/null 2>&1

# Remove icon from config file
if [[ -f "$ICONS_FILE" ]]; then
    sed -i "/^${WS_NUM}:/d" "$ICONS_FILE"
fi

# Recalculate bar width and restart workspaces bar
sleep 0.2
WS_COUNT=$(i3-msg -t get_workspaces | jq 'length')
[[ $WS_COUNT -lt $MIN_WS ]] && WS_COUNT=$MIN_WS
export WS_BAR_WIDTH=$((2*EDGE_PADDING + WS_COUNT*ICON_WIDTH + (WS_COUNT-1)*GAP))
export WS_ADD_OFFSET=$((GAPS_OUTER + WS_BAR_WIDTH + 4))

# Restart only workspaces and workspace-add bars
pkill -f "polybar.*workspaces" || true
pkill -f "polybar.*workspace-add" || true
sleep 0.1
polybar --reload workspaces &
polybar --reload workspace-add &
