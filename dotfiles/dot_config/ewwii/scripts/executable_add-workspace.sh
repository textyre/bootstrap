#!/bin/bash
# ============================================================
# Add New Workspace with Icon Selection
# Opens rofi menu to choose icon, then creates workspace
# Size/position updates are handled by ewwii listen() automatically
# ============================================================

set -euo pipefail

# Source layout constants
source ~/.config/layout-constants.sh 2>/dev/null || {
    MAX_WORKSPACES=10
}

# Icon options for rofi
ICONS=(
    "  Terminal"
    "  Browser"
    "  Code"
    "  Files"
    "  Music"
    "  Video"
    "  Chat"
    "󰇮  Email"
    "  Gaming"
    "  Work"
)

# Get next available workspace number
get_next_ws() {
    local current_ws
    current_ws=$(i3-msg -t get_workspaces | jq '[.[].num] | sort | .[-1]')
    echo $((current_ws + 1))
}

# Get current workspace count
get_ws_count() {
    i3-msg -t get_workspaces | jq 'length'
}

# Check if at max workspaces
ws_count=$(get_ws_count)
if [[ $ws_count -ge ${MAX_WORKSPACES:-10} ]]; then
    notify-send "Workspaces" "Maximum workspaces ($MAX_WORKSPACES) reached" -u warning
    exit 0
fi

# Show rofi menu
selected=$(printf '%s\n' "${ICONS[@]}" | rofi -dmenu -p "New Workspace Icon" -theme-str 'window {width: 300px;}')

if [[ -z "$selected" ]]; then
    exit 0
fi

# Extract icon (first word/character before space)
icon="${selected%% *}"

# Get next workspace number
next_ws=$(get_next_ws)

# Save icon to config
ICON_FILE="${HOME}/.config/ewwii/workspace-icons.conf"
mkdir -p "$(dirname "$ICON_FILE")"
echo "${next_ws}=${icon}" >> "$ICON_FILE"

# Create and switch to new workspace
# This triggers i3 workspace event which updates ewwii via listen()
i3-msg "workspace number ${next_ws}"

notify-send "Workspace ${next_ws}" "Created with icon ${icon}"
