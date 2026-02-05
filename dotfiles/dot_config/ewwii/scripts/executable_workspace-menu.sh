#!/bin/bash
# Workspace context menu (right-click)
# Shows options: Change Icon, Close Workspace

set -euo pipefail

# Source layout constants
source ~/.config/layout-constants.sh 2>/dev/null || {
    MIN_WORKSPACES=3
}

# Get workspace number from argument
ws_num="${1:-}"
if [[ -z "$ws_num" ]]; then
    echo "Usage: $0 <workspace_number>" >&2
    exit 1
fi

# Menu options
OPTIONS=(
    "󰏘  Change Icon"
    "  Close Workspace"
)

# Don't show close option for base workspaces
if [[ $ws_num -le ${MIN_WORKSPACES:-3} ]]; then
    OPTIONS=("󰏘  Change Icon")
fi

# Show rofi menu
selected=$(printf '%s\n' "${OPTIONS[@]}" | rofi -dmenu -p "Workspace ${ws_num}" -theme-str 'window {width: 250px;}')

case "$selected" in
    *"Change Icon"*)
        ~/.config/ewwii/scripts/change-icon.sh "$ws_num"
        ;;
    *"Close Workspace"*)
        # Switch to this workspace first, then close
        i3-msg "workspace number ${ws_num}"
        ~/.config/ewwii/scripts/close-workspace.sh
        ;;
esac
