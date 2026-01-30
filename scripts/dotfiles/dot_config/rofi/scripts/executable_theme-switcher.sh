#!/bin/bash
# Rofi Theme Switcher — select and apply theme via chezmoi

themes=$(chezmoi data --format=json 2>/dev/null | jq -r '.themes | keys[]')

if [ -z "$themes" ]; then
    notify-send -u critical "Theme Switcher" "Could not read themes from chezmoi data"
    exit 1
fi

chosen=$(echo "$themes" | rofi -dmenu -theme ~/.config/rofi/themes/theme-switcher.rasi -p " Theme")

if [ -n "$chosen" ]; then
    ~/.local/bin/theme-switch "$chosen"
fi
