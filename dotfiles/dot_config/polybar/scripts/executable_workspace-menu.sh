#!/usr/bin/env bash

set -euo pipefail

WS_NUM="$1"

# Menu options
OPTIONS=" Сменить иконку
 Закрыть воркспейс"

SELECTED=$(echo -e "$OPTIONS" | rofi -dmenu -p "Воркспейс $WS_NUM" -theme ~/.config/rofi/themes/context-menu.rasi 2>/dev/null) || exit 0

case "$SELECTED" in
    *"Сменить иконку"*)
        ~/.config/polybar/scripts/change-workspace-icon.sh "$WS_NUM"
        ;;
    *"Закрыть"*)
        ~/.config/polybar/scripts/close-workspace.sh "$WS_NUM"
        ;;
esac
