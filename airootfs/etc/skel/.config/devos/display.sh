#!/bin/sh
# DevOS per-machine display setup.
#
# Sourced indirectly by ~/.xinitrc (live ISO / startx) and /etc/xprofile
# (installed system / SDDM) right before the XFCE session starts. Nothing here
# is tied to a specific connector name: the default wallpaper is applied to
# whatever output(s) are connected RIGHT NOW, so the same image works on any
# MacBook panel (eDP1, eDP-1, eDP-1-1, ...). This is what stops the wallpaper
# from silently failing to apply when a machine enumerates its panel under a
# different name than the connector a static xfce4-desktop.xml was captured with.

WALLPAPER=/usr/share/backgrounds/devos/boliviainteligente-37WxvlfW3to-unsplash.jpg

command -v xrandr >/dev/null 2>&1 || exit 0

# Default the INTERNAL panel (eDP*) to 1680x1050@60 (16:10) — but only on the
# FIRST session on this machine (stamp file), only when the panel actually
# advertises that mode, and never again afterwards: a resolution the user picks
# later (xfce4-display writes its own profile) must not be clobbered per login.
# displays.xml deliberately ships NO Default profile (connector names differ
# across MacBooks), so this hook is the one portable place for a default mode.
RES_STAMP="$HOME/.config/devos/.default-resolution-applied"
if [ ! -e "$RES_STAMP" ]; then
    INTERNAL=$(xrandr --query | awk '/^eDP[^ ]* connected|^eDP connected/ {print $1; exit}')
    if [ -n "$INTERNAL" ] && xrandr --query | awk -v out="$INTERNAL" '
            index($0, out " connected") == 1 {inout = 1; next}
            /^[^ ]/                          {inout = 0}
            inout && $1 == "1680x1050"       {found = 1}
            END {exit !found}'; then
        xrandr --output "$INTERNAL" --mode 1680x1050 --rate 60 2>/dev/null \
            || xrandr --output "$INTERNAL" --mode 1680x1050 2>/dev/null
    fi
    mkdir -p "${RES_STAMP%/*}" && : > "$RES_STAMP"
fi

command -v xfconf-query >/dev/null 2>&1 || exit 0
[ -r "$WALLPAPER" ] || exit 0

# Set an xfce4-desktop property ONLY if it doesn't exist yet. This applies the
# default for a connector name we've never seen (the wrong-name bug) WITHOUT
# overwriting a wallpaper the user later picks — that user choice is what
# devos-sddm-wallpaper-sync mirrors onto the SDDM login screen, so clobbering it
# here every login would defeat the whole point.
set_default() {
    prop="$1"; type="$2"; value="$3"
    xfconf-query -c xfce4-desktop -p "$prop" >/dev/null 2>&1 && return 0  # exists: respect it
    xfconf-query -c xfce4-desktop -p "$prop" -n -t "$type" -s "$value" 2>/dev/null
}

# xfdesktop keys its backdrop by monitor name, so set it for whatever connectors
# exist now instead of relying on a fixed name baked into xfce4-desktop.xml.
for OUT in $(xrandr --query | awk '/ connected/ {print $1}'); do
    base="/backdrop/screen0/monitor${OUT}/workspace0"
    set_default "$base/last-image"  string "$WALLPAPER"
    set_default "$base/image-style" int    5            # 5 = Zoomed: fills any resolution
done

exit 0
