#!/bin/bash
# Rofi Wallpaper Picker — browse and select

WALLPAPER_DIR="$HOME/.local/share/wallpapers"

if [ ! -d "$WALLPAPER_DIR" ]; then
    notify-send "Wallpaper Picker" "Directory not found: $WALLPAPER_DIR" -u critical
    exit 1
fi

files=$(find "$WALLPAPER_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.webp" \) | sort)

if [ -z "$files" ]; then
    notify-send "Wallpaper Picker" "No wallpapers found" -u normal
    exit 1
fi

chosen=$(echo "$files" | xargs -I{} basename {} | rofi -dmenu -theme ~/.config/rofi/themes/wallpaper-picker.rasi -p " Wallpaper")

if [ -n "$chosen" ]; then
    full_path=$(find "$WALLPAPER_DIR" -name "$chosen" -type f | head -1)
    if [ -n "$full_path" ]; then
        ~/.local/bin/wallpaper-set "$full_path"
    fi
fi
