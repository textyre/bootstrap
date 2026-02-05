#!/bin/bash
# ============================================================
# Close Workspace and Move Windows to Workspace 1
# Size/position updates are handled by ewwii listen() automatically
# ============================================================

set -euo pipefail

# Source layout constants
source ~/.config/layout-constants.sh 2>/dev/null || {
    MIN_WORKSPACES=3
}

# Get current workspace number
current_ws=$(i3-msg -t get_workspaces | jq '.[] | select(.focused) | .num')

# Don't close workspaces 1-3 (base workspaces)
if [[ $current_ws -le ${MIN_WORKSPACES:-3} ]]; then
    notify-send "Workspaces" "Cannot close base workspaces (1-${MIN_WORKSPACES:-3})" -u warning
    exit 0
fi

# Move all windows from current workspace to workspace 1
i3-msg "[workspace=${current_ws}] move container to workspace number 1" 2>/dev/null || true

# Switch to workspace 1
# This triggers i3 workspace event which updates ewwii via listen()
i3-msg "workspace number 1"

# Remove icon from config file
ICON_FILE="${HOME}/.config/ewwii/workspace-icons.conf"
if [[ -f "$ICON_FILE" ]]; then
    sed -i "/^${current_ws}=/d" "$ICON_FILE" 2>/dev/null || true
fi

notify-send "Workspace ${current_ws}" "Closed, windows moved to workspace 1"
