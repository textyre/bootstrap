#!/usr/bin/env bash

set -euo pipefail

WS_NUM="$1"
ICONS_FILE="$HOME/.config/polybar/workspace-icons.conf"

# Available icons
ICONS="● Круг (по умолчанию)
 Terminal
 Code
 Browser
 Files
 Chat
 Music
 Video
 Gaming
 Settings
 Notes"

SELECTED=$(echo -e "$ICONS" | rofi -dmenu -p "Иконка" -theme ~/.config/rofi/themes/icon-select.rasi 2>/dev/null) || exit 0

if [[ -z "$SELECTED" ]]; then
    exit 0
fi

ICON=$(echo "$SELECTED" | awk '{print $1}')

# Ensure config directory exists
mkdir -p "$(dirname "$ICONS_FILE")"

# Remove old icon for this workspace
if [[ -f "$ICONS_FILE" ]]; then
    sed -i "/^${WS_NUM}:/d" "$ICONS_FILE"
fi

# Add new icon
echo "${WS_NUM}:${ICON}" >> "$ICONS_FILE"
