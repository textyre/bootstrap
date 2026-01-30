#!/bin/bash
# Rofi Power Menu

lock=""
logout=""
suspend=""
reboot=""
shutdown=""

options="$lock\n$logout\n$suspend\n$reboot\n$shutdown"

chosen=$(echo -e "$options" | rofi -dmenu -mesg "Power Menu" -theme ~/.config/rofi/themes/powermenu.rasi -p "")

case "$chosen" in
    "$lock")     ~/.local/bin/lock-screen ;;
    "$logout")   i3-msg exit ;;
    "$suspend")  systemctl suspend ;;
    "$reboot")   systemctl reboot ;;
    "$shutdown") systemctl poweroff ;;
esac
