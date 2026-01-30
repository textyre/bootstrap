#!/bin/bash
# Rofi Theme Switcher — select and apply theme via chezmoi

themes="dracula\nmonochrome"

chosen=$(echo -e "$themes" | rofi -dmenu -theme ~/.config/rofi/themes/theme-switcher.rasi -p " Theme")

if [ -n "$chosen" ]; then
    ~/.local/bin/theme-switch "$chosen"
fi
