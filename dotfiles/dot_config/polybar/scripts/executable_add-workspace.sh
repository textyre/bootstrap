#!/usr/bin/env bash

set -euo pipefail

ICONS_FILE="$HOME/.config/polybar/workspace-icons.conf"

# Available icons (default first)
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

# Show rofi menu for icon selection
SELECTED=$(echo -e "$ICONS" | rofi -dmenu -p "Иконка воркспейса" -theme ~/.config/rofi/themes/icon-select.rasi 2>/dev/null) || exit 0

if [[ -z "$SELECTED" ]]; then
    exit 0
fi

ICON=$(echo "$SELECTED" | awk '{print $1}')

# Find first free workspace number (4-10)
for i in {4..10}; do
    if ! i3-msg -t get_workspaces | jq -e ".[] | select(.num == $i)" > /dev/null 2>&1; then
        # Ensure config directory exists
        mkdir -p "$(dirname "$ICONS_FILE")"

        # Save icon to config file
        echo "${i}:${ICON}" >> "$ICONS_FILE"

        # Switch to new workspace
        i3-msg "workspace number $i" >/dev/null 2>&1

        # Restart polybar to recalculate bar widths
        sleep 0.1
        ~/.config/polybar/launch.sh &

        exit 0
    fi
done

# All workspaces are occupied
notify-send "Polybar" "Максимум 10 воркспейсов" -u warning
