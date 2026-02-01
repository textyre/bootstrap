#!/bin/bash
# Polybar launch script — three floating island bars
# Terminates existing instances and launches fresh

killall -q polybar

while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done

if type "xrandr" >/dev/null 2>&1; then
    for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        MONITOR=$m polybar --reload workspaces &
        MONITOR=$m polybar --reload clock &
        MONITOR=$m polybar --reload system &
    done
else
    polybar --reload workspaces &
    polybar --reload clock &
    polybar --reload system &
fi
