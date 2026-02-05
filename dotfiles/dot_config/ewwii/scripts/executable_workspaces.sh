#!/bin/bash
# ============================================================
# Workspaces JSON Generator for Ewwii
# Outputs JSON array of workspaces on i3 events
# Supports custom icons from workspace-icons.conf
# ============================================================

set -euo pipefail

# Custom icon file
ICON_FILE="${HOME}/.config/ewwii/workspace-icons.conf"

# Default icons for workspaces 1-10
declare -A DEFAULT_ICONS=(
    [1]="🌍"
    [2]="󰀫"
    [3]="󰀛"
    [4]=""
    [5]=""
    [6]=""
    [7]=""
    [8]=""
    [9]=""
    [10]=""
)

# Get icon for workspace (custom or default)
get_icon() {
    local ws_num="$1"

    # Check custom icon file first
    if [[ -f "$ICON_FILE" ]]; then
        local custom_icon
        custom_icon=$(grep "^${ws_num}=" "$ICON_FILE" 2>/dev/null | cut -d= -f2 | head -1)
        if [[ -n "$custom_icon" ]]; then
            echo "$custom_icon"
            return
        fi
    fi

    # Return default icon
    echo "${DEFAULT_ICONS[$ws_num]:-$ws_num}"
}

# Generate workspaces JSON with custom icons
generate_json() {
    local workspaces
    workspaces=$(i3-msg -t get_workspaces 2>/dev/null) || return

    # Build JSON with custom icons
    local result="["
    local first=true

    while read -r ws; do
        local num name focused urgent visible windows
        num=$(echo "$ws" | jq -r '.num')
        name=$(echo "$ws" | jq -r '.name')
        focused=$(echo "$ws" | jq -r '.focused')
        urgent=$(echo "$ws" | jq -r '.urgent')
        visible=$(echo "$ws" | jq -r '.visible')
        windows=$(echo "$ws" | jq -r '.windows // 0')

        # Get icon (custom or default)
        local icon
        icon=$(get_icon "$num")

        # Determine state
        local state
        if [[ "$focused" == "true" ]]; then
            state="focused"
        elif [[ "$urgent" == "true" ]]; then
            state="urgent"
        elif [[ "$visible" == "true" ]] || [[ "$windows" -gt 0 ]]; then
            state="occupied"
        else
            state="empty"
        fi

        # Build JSON object
        local ws_json
        ws_json=$(jq -nc \
            --argjson number "$num" \
            --arg name "$name" \
            --arg icon "$icon" \
            --arg state "$state" \
            '{number: $number, name: $name, icon: $icon, state: $state}')

        if [[ "$first" == "true" ]]; then
            first=false
            result+="$ws_json"
        else
            result+=",$ws_json"
        fi
    done < <(echo "$workspaces" | jq -c '.[]')

    result+="]"
    echo "$result"
}

# Output initial state
generate_json

# Subscribe to i3 workspace events and regenerate on change
i3-msg -t subscribe '["workspace"]' --monitor 2>/dev/null | while read -r _; do
    generate_json
done
