#!/bin/bash
#
# ACPI lid handler with explicit suspend policy
# - Deterministic display handling
# - Explicit suspend when no external display
# - Compatible with multiple startx users
#

set -eu

# -------------------------------------------------
# Configuration
# -------------------------------------------------
LOGFILE="/var/log/lid-handler.log"
STATEFILE="/run/lid-handler.state"

INTERNAL="eDP1"
EXTERNAL="DP2"

INT_MODE="1680x1050"
EXT_MODE="2560x1440"
EXT_RATE="60"

# -------------------------------------------------
# Detect active user on tty1 (startx)
# -------------------------------------------------
ACTIVE_USER=$(who | awk '/tty1/ {print $1; exit}')
DISPLAY=":0"
XAUTHORITY="/home/$ACTIVE_USER/.Xauthority"
export DISPLAY XAUTHORITY

# -------------------------------------------------
# Read lid state
# -------------------------------------------------
LID_STATE=$(grep -o 'open\|closed' /proc/acpi/button/lid/*/state)

# Suppress duplicate events
LAST_STATE="$(cat "$STATEFILE" 2>/dev/null || true)"
if [ "$LAST_STATE" = "$LID_STATE" ]; then
    exit 0
fi
echo "$LID_STATE" > "$STATEFILE"

# -------------------------------------------------
# Logging helper
# -------------------------------------------------
log() {
    printf '%s | lid=%s | user=%s | dp2=%s | %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$LID_STATE" \
        "${ACTIVE_USER:-none}" \
        "${DP2_CONNECTED:-unknown}" \
        "$1" >> "$LOGFILE"
}

# -------------------------------------------------
# Probe external display
# -------------------------------------------------
if /usr/bin/xrandr --query | grep -q "^$EXTERNAL connected"; then
    DP2_CONNECTED="yes"
else
    DP2_CONNECTED="no"
fi
log "probe complete: DP2_CONNECTED=$DP2_CONNECTED"

# -------------------------------------------------
# Suspend helper
# -------------------------------------------------
suspend_system() {
    log "suspending system"
    logger "lid.handler: suspending system"
    /usr/bin/systemctl suspend
}

# -------------------------------------------------
# Apply lid policy
# -------------------------------------------------
if [ "$LID_STATE" = "open" ]; then
    if [ "$DP2_CONNECTED" = "yes" ]; then
        /usr/bin/xrandr \
            --output "$INTERNAL" --mode "$INT_MODE" --pos 0x0 \
            --output "$EXTERNAL" --mode "$EXT_MODE" --rate "$EXT_RATE" \
            --pos ${INT_MODE%x*}x0 --primary
        log "lid open: dual display restored"
    else
        /usr/bin/xrandr --output "$INTERNAL" --mode "$INT_MODE" --primary
        log "lid open: internal only"
    fi

    # Start xfdashboard if not already running
    if ! pgrep -u "$ACTIVE_USER" xfdashboard >/dev/null; then
        su - "$ACTIVE_USER" -c 'sleep 2; DISPLAY=:0 XAUTHORITY=/home/'"$ACTIVE_USER"'/.Xauthority /usr/bin/xfdashboard &'
    fi

else
    # Lid closed
    if [ "$DP2_CONNECTED" = "yes" ]; then
        /usr/bin/xrandr \
            --output "$INTERNAL" --off \
            --output "$EXTERNAL" --mode "$EXT_MODE" --rate "$EXT_RATE" --primary
        log "lid closed: internal off, external primary"
    else
        suspend_system
    fi
fi


exit 0
