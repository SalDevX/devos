#!/bin/sh
STATE="$HOME/.reaper_mode"

if [ -f "$STATE" ]; then
    xmodmap -e "clear Mod3"
    xmodmap ~/.Xmodmap.normal
    rm "$STATE"
    notify-send "Mode: NORMAL" "Caps Lock restored, Super grabs windows"
else
    xmodmap -e "clear Mod3"
    xmodmap ~/.Xmodmap.reaper
    touch "$STATE"
    notify-send "Mode: REAPER" "Caps Lock grabs windows"
fi
