#!/bin/bash
# Polybar launch script — floating island bars
# Terminates existing instances and launches fresh

killall -q polybar

while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done

# Layout constants
GAPS_OUTER=${GAPS_OUTER:-8}
EDGE_PADDING=12
GAP=22
ICON_WIDTH=16
MIN_WS=3

# Count current workspaces (minimum 3)
WS_COUNT=$(i3-msg -t get_workspaces 2>/dev/null | jq 'length' 2>/dev/null || echo 3)
[[ $WS_COUNT -lt $MIN_WS ]] && WS_COUNT=$MIN_WS

# Calculate workspaces bar width: 2*edge + N*icon + (N-1)*gap
export WS_BAR_WIDTH=$((2*EDGE_PADDING + WS_COUNT*ICON_WIDTH + (WS_COUNT-1)*GAP))

# Calculate offset for workspace-add button
export WS_ADD_OFFSET=$((GAPS_OUTER + WS_BAR_WIDTH + 4))

if type "xrandr" >/dev/null 2>&1; then
    for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        MONITOR=$m polybar --reload workspaces &
        MONITOR=$m polybar --reload workspace-add &
        MONITOR=$m polybar --reload clock &
        MONITOR=$m polybar --reload system &
    done
else
    polybar --reload workspaces &
    polybar --reload workspace-add &
    polybar --reload clock &
    polybar --reload system &
fi
