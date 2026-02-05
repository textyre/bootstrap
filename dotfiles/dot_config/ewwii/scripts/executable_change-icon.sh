#!/bin/bash
# Change icon for a workspace
# Opens rofi menu to select new icon

set -euo pipefail

# Get workspace number from argument or current
ws_num="${1:-}"
if [[ -z "$ws_num" ]]; then
    ws_num=$(i3-msg -t get_workspaces | jq '.[] | select(.focused) | .num')
fi

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
    "🌍  World"
    "󰀫  Dots"
    "󰀛  Grid"
)

# Show rofi menu
selected=$(printf '%s\n' "${ICONS[@]}" | rofi -dmenu -p "Change Icon (WS ${ws_num})" -theme-str 'window {width: 300px;}')

if [[ -z "$selected" ]]; then
    exit 0
fi

# Extract icon (first word/character before space)
icon="${selected%% *}"

# Save icon to config file
ICON_FILE="${HOME}/.config/ewwii/workspace-icons.conf"
mkdir -p "$(dirname "$ICON_FILE")"

# Remove old entry if exists
if [[ -f "$ICON_FILE" ]]; then
    sed -i "/^${ws_num}=/d" "$ICON_FILE" 2>/dev/null || true
fi

# Add new entry
echo "${ws_num}=${icon}" >> "$ICON_FILE"

notify-send "Workspace ${ws_num}" "Icon changed to ${icon}"
