#!/usr/bin/env bash

set -euo pipefail

WS_NUM="$1"
ICONS_FILE="$HOME/.config/polybar/workspace-icons.conf"

# Move all windows from this workspace to workspace 1
i3-msg "[workspace=$WS_NUM] move to workspace 1" >/dev/null 2>&1 || true

# Switch to workspace 1
i3-msg "workspace 1" >/dev/null 2>&1

# Remove icon from config file
if [[ -f "$ICONS_FILE" ]]; then
    sed -i "/^${WS_NUM}:/d" "$ICONS_FILE"
fi

# Restart polybar to recalculate bar widths
sleep 0.2
~/.config/polybar/launch.sh &
