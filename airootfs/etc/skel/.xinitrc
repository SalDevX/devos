#!/bin/sh
# DevOS default X session: XFCE. (RT/dwm session lives in the separate MusicOS project.)

export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce

# Optional per-machine display setup (resolution, scaling). Create this script
# to run xrandr etc.; nothing is hardcoded so the image is hardware-agnostic.
[ -x "$HOME/.config/devos/display.sh" ] && "$HOME/.config/devos/display.sh"

# Per-machine panel setup: weather location from the installed timezone + dynamic
# netload interface. Runs before the panel starts so the panel picks it up.
[ -x "$HOME/.config/devos/panel-dynamic.sh" ] && "$HOME/.config/devos/panel-dynamic.sh"

exec startxfce4
