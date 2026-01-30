#!/bin/bash
# Rofi Power Menu

lock=""
logout=""
suspend=""
reboot=""
shutdown=""

options="$lock\n$logout\n$suspend\n$reboot\n$shutdown"

chosen=$(echo -e "$options" | rofi -dmenu -mesg "Power Menu" -theme ~/.config/rofi/themes/powermenu.rasi -p "")

confirm_action() {
    local answer
    answer=$(echo -e "Yes\nNo" | rofi -dmenu -mesg "Are you sure?" -theme ~/.config/rofi/themes/powermenu.rasi -p "")
    [[ "$answer" == "Yes" ]]
}

case "$chosen" in
    "$lock")     ~/.local/bin/lock-screen ;;
    "$logout")   confirm_action && i3-msg exit ;;
    "$suspend")  systemctl suspend ;;
    "$reboot")   confirm_action && systemctl reboot ;;
    "$shutdown") confirm_action && systemctl poweroff ;;
esac
