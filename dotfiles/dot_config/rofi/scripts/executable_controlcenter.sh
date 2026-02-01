#!/bin/bash
# Rofi Control Center
set -euo pipefail

# Gather current state
get_volume() {
    if command -v pamixer &>/dev/null; then
        if pamixer --get-mute | grep -q "true"; then
            echo "MUTED"
        else
            echo "$(pamixer --get-volume)%"
        fi
    else
        echo "N/A"
    fi
}

get_brightness() {
    if command -v brightnessctl &>/dev/null; then
        echo "$(brightnessctl -m | cut -d',' -f4)"
    else
        echo "N/A"
    fi
}

get_network() {
    if command -v nmcli &>/dev/null; then
        local network
        network=$(nmcli -t -f NAME connection show --active | head -1)
        if [[ -n "$network" ]]; then
            echo "$network"
        else
            echo "Disconnected"
        fi
    else
        echo "N/A"
    fi
}

# Build menu options
volume_icon=""
brightness_icon=""
network_icon=""
display_icon=""
power_icon=""

volume_status=$(get_volume)
brightness_status=$(get_brightness)
network_status=$(get_network)

options="${volume_icon}  Volume: ${volume_status}\n"
options+="${brightness_icon}  Brightness: ${brightness_status}\n"
options+="${network_icon}  Network: ${network_status}\n"
options+="${display_icon}  Display Settings\n"
options+="${power_icon}  Power Menu"

# Show rofi menu
chosen=$(echo -e "$options" | rofi -dmenu -mesg "Control Center" -theme ~/.config/rofi/themes/controlcenter.rasi -p "")

# Handle selections
case "$chosen" in
    "${volume_icon}  Volume:"*)
        if command -v pavucontrol &>/dev/null; then
            pavucontrol &
        fi
        ;;
    "${brightness_icon}  Brightness:"*)
        if command -v brightnessctl &>/dev/null; then
            current=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')
            if [[ $current -lt 25 ]]; then
                brightnessctl set 25%
            elif [[ $current -lt 50 ]]; then
                brightnessctl set 50%
            elif [[ $current -lt 75 ]]; then
                brightnessctl set 75%
            elif [[ $current -lt 100 ]]; then
                brightnessctl set 100%
            else
                brightnessctl set 25%
            fi
        fi
        ;;
    "${network_icon}  Network:"*)
        if command -v alacritty &>/dev/null && command -v nmtui &>/dev/null; then
            alacritty -e nmtui &
        fi
        ;;
    "${display_icon}  Display Settings")
        if command -v arandr &>/dev/null; then
            arandr &
        fi
        ;;
    "${power_icon}  Power Menu")
        if [[ -x ~/.config/rofi/scripts/powermenu.sh ]]; then
            ~/.config/rofi/scripts/powermenu.sh &
        fi
        ;;
esac
