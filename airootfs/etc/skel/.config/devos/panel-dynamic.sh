#!/bin/sh
# DevOS per-machine panel setup — runs at session start (/etc/xprofile + ~/.xinitrc)
# BEFORE xfce4-panel loads, so the panel picks up what we set here. Nothing is
# hardcoded to a host/interface, so the image stays hardware-agnostic.
#
#  * Weather (xfce4-weather-plugin): the shipped skel panel has an EMPTY location.
#    On first login we fill it from the timezone the Calamares installer chose
#    (/etc/timezone) mapped to lat/lon via /usr/share/zoneinfo/zone1970.tab — only
#    while still empty, so a user's later manual choice is never overwritten.
#  * Netload (xfce4-netload-plugin): the shipped device name is the build host's;
#    each login we rewrite it to THIS machine's active default-route interface so
#    the monitor always tracks the live device.

command -v xfconf-query >/dev/null 2>&1 || exit 0
PANEL=xfce4-panel

# plugin-N id of the first panel plugin of the given type. Detected at runtime so
# this keeps working if the panel is re-exported / the plugins are renumbered.
find_plugin() {
    for pid in $(xfconf-query -c "$PANEL" -p /plugins -l 2>/dev/null \
                 | sed -n 's@^/plugins/\(plugin-[0-9]\{1,\}\)$@\1@p'); do
        [ "$(xfconf-query -c "$PANEL" -p "/plugins/$pid" 2>/dev/null)" = "$1" ] \
            && { echo "$pid"; return 0; }
    done
    return 1
}

setprop() {  # setprop <full-prop-path> <string-value>  (set, or create if absent)
    xfconf-query -c "$PANEL" -p "$1" -s "$2" 2>/dev/null \
        || xfconf-query -c "$PANEL" -p "$1" -n -t string -s "$2" 2>/dev/null
}

# ----- Weather: location from the installed timezone (only while unset) ------
wp=$(find_plugin weather)
ZONETAB=/usr/share/zoneinfo/zone1970.tab
if [ -n "$wp" ] && [ -r "$ZONETAB" ]; then
    cur=$(xfconf-query -c "$PANEL" -p "/plugins/$wp/location/latitude" 2>/dev/null)
    if [ -z "$cur" ]; then
        tz=$(cat /etc/timezone 2>/dev/null)
        [ -z "$tz" ] && tz=$(readlink -f /etc/localtime 2>/dev/null | sed 's@.*/zoneinfo/@@')
        if [ -n "$tz" ]; then
            # zone1970.tab: <codes> <±DDMM[SS]±DDDMM[SS]> <TZ> [comments]. Convert the
            # ISO-6709 coordinate to decimal (lat = 2 degree digits, lon = 3).
            set -- $(awk -v tz="$tz" '
                function dec(s, degd,   sg,b,deg,rest,mn,sc) {
                    sg = (substr(s,1,1)=="-") ? -1 : 1; b = substr(s,2)
                    deg = substr(b,1,degd); rest = substr(b,degd+1)
                    mn = substr(rest,1,2); sc = substr(rest,3,2); if (sc=="") sc=0
                    return sg * (deg + mn/60 + sc/3600)
                }
                $3==tz {
                    c=$2
                    for (i=2;i<=length(c);i++){ ch=substr(c,i,1); if(ch=="+"||ch=="-"){p=i;break} }
                    printf "%.6f %.6f\n", dec(substr(c,1,p-1),2), dec(substr(c,p),3); exit
                }' "$ZONETAB")
            if [ -n "$1" ] && [ -n "$2" ]; then
                setprop "/plugins/$wp/location/latitude"  "$1"
                setprop "/plugins/$wp/location/longitude" "$2"
                setprop "/plugins/$wp/location/name"      "$(echo "${tz##*/}" | tr '_' ' ')"
                setprop "/plugins/$wp/timezone"           "$tz"
            fi
        fi
    fi
fi

# ----- Netload: track the live default-route interface -----------------------
np=$(find_plugin netload)
if [ -n "$np" ]; then
    rc="$HOME/.config/xfce4/panel/netload-${np#plugin-}.rc"
    dev=$(ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
    [ -z "$dev" ] && dev=$(ls /sys/class/net 2>/dev/null | grep -vx lo | head -n1)
    if [ -n "$dev" ] && [ -f "$rc" ]; then
        if grep -q '^Network_Device=' "$rc"; then
            sed -i "s/^Network_Device=.*/Network_Device=$dev/" "$rc"
        else
            printf 'Network_Device=%s\n' "$dev" >> "$rc"
        fi
    fi
fi

exit 0
