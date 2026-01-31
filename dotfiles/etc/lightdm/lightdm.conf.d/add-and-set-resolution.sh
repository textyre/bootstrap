#!/bin/bash
set -x

x="$1"
y="$2"
freq="$3"

if [ $# -ne 3 ]; then
echo "Usage: $0 x y freq"
echo "To find output name: xrandr -q"
exit 0
fi

output=$( xrandr | (grep -m1 ' connected primary' || grep -m1 ' connected') | cut -d' ' -f1 )
mode=$( cvt "$x" "$y" "$freq" | grep -v '^#' | cut -d' ' -f3- )
modename="${x}x${y}"

xrandr --newmode $modename $mode
xrandr --addmode "$output" "$modename"
xrandr --output "$output" --mode "$modename"

# Always return success or lightdm goes into infinite loop
exit 0