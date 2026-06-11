#!/bin/bash
#
# ACPI lid handler with explicit suspend policy
# - Dynamic display detection (no burned-in connector names or modes)
# - Explicit suspend when no external display
# - Compatible with multiple startx users
# - Spurious-wake debounce for Apple EC (re-suspends if it bounces out of S3)
#

set -eu

# -------------------------------------------------
# Configuration
# -------------------------------------------------
LOGFILE="/var/log/lid-handler.log"
STATEFILE="/run/lid-handler.state"

# Spurious-wake debounce (the Apple EC can bounce back out of S3 right after
# we suspend, because the lid-close GPE is still pending once a wake source is
# armed). After each resume we re-check the lid and re-suspend if it's still
# shut -- capped so a *different* wake source can't trap us in a drain loop.
SUSPEND_SETTLE=2        # seconds to let the EC settle after a resume before re-checking the lid
SUSPEND_MAX_RETRIES=3   # how many spurious wakes to re-suspend through before giving up

# -------------------------------------------------
# Detect the active graphical user.
#  - startx (live ISO): the user owns the session on tty1
#  - SDDM (installed):  fall back to the owner of the running Xorg process
# -------------------------------------------------
ACTIVE_USER=$(who | awk '/tty1/ {print $1; exit}')
[ -n "${ACTIVE_USER:-}" ] || ACTIVE_USER=$(ps -o user= -C Xorg -C X 2>/dev/null | head -1)

DISPLAY=":0"
XAUTHORITY="/home/$ACTIVE_USER/.Xauthority"
export DISPLAY XAUTHORITY

# GUI apps relaunched as the user (Plank, xfdashboard) need the FULL session
# environment, not just X: without XDG_RUNTIME_DIR + the session DBus address a
# su-launched GTK app can't reach the user bus and exits immediately ("dock
# vanished after a lid event"). `su -` does not inherit these, so build them
# explicitly from the user's UID and hand them to every in-session command.
SESSION_ENV=""
if [ -n "${ACTIVE_USER:-}" ]; then
    USER_UID=$(id -u "$ACTIVE_USER" 2>/dev/null || true)
    XDG_RUNTIME_DIR="/run/user/$USER_UID"
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"
    export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS
    SESSION_ENV="DISPLAY=:0 XAUTHORITY='$XAUTHORITY' XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'"
fi

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
# Detect displays dynamically (NO hardcoded connector names or modes).
# INTERNAL = first connected eDP* panel; EXTERNAL = first connected non-eDP.
# Connector names differ across MacBooks (eDP1 / eDP-1 / eDP-1-1, DP2 / DP-1 /
# HDMI-1), so we never burn one in -- this is the same class of bug that left
# the wallpaper pinned to a stale connector. Modes come from --auto (native).
# -------------------------------------------------
INTERNAL=$(/usr/bin/xrandr --query 2>/dev/null | awk '/ connected/ && $1 ~ /^eDP/  {print $1; exit}')
EXTERNAL=$(/usr/bin/xrandr --query 2>/dev/null | awk '/ connected/ && $1 !~ /^eDP/ {print $1; exit}')

if [ -n "$EXTERNAL" ]; then
    EXTERNAL_CONNECTED="yes"
else
    EXTERNAL_CONNECTED="no"
fi

# -------------------------------------------------
# Logging helper
# -------------------------------------------------
log() {
    printf '%s | lid=%s | user=%s | internal=%s | external=%s | %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$LID_STATE" \
        "${ACTIVE_USER:-none}" \
        "${INTERNAL:-none}" \
        "${EXTERNAL:-none}" \
        "$1" >> "$LOGFILE"
}

log "probe complete: EXTERNAL_CONNECTED=$EXTERNAL_CONNECTED"

# -------------------------------------------------
# Suspend helper (with spurious-wake debounce)
# -------------------------------------------------
suspend_system() {
    local attempt=0
    while : ; do
        log "suspending system (attempt $((attempt + 1)))"
        logger "lid.handler: suspending system (attempt $((attempt + 1)))"

        # Blocks here until the machine wakes back up.
        /usr/bin/systemctl suspend || log "systemctl suspend returned non-zero"

        # Execution resumes only AFTER a wake. Give the embedded controller a
        # moment to settle the lid GPE before deciding real wake vs. EC bounce.
        sleep "$SUSPEND_SETTLE"

        local now_state
        now_state=$(grep -o 'open\|closed' /proc/acpi/button/lid/*/state | head -1 || true)

        if [ "$now_state" = "open" ]; then
            log "resumed with lid OPEN -> genuine wake; leaving suspend loop"
            return 0
        fi

        attempt=$((attempt + 1))
        if [ "$attempt" -ge "$SUSPEND_MAX_RETRIES" ]; then
            log "resumed with lid CLOSED ${attempt}x -> spurious-wake cap reached; staying awake"
            logger "lid.handler: spurious-wake guard hit cap; staying awake"
            return 0
        fi
        log "resumed with lid CLOSED -> spurious wake; re-suspending"
    done
}

# -------------------------------------------------
# Re-anchor Plank after a layout change. Plank does not follow RandR, so once
# the outputs move it can be stranded on a now-offscreen primary. Restart it so
# it re-attaches to the new primary -- but ONLY if it is already running, since
# Plank.desktop owns first launch at login and not every session uses a dock.
# Mirrors the live-system display-layout.sh --dock behaviour: kill, wait for the
# single-instance DBus name to release, then relaunch detached via setsid.
# -------------------------------------------------
reanchor_plank() {
    [ -n "${ACTIVE_USER:-}" ] || return 0
    pgrep -u "$ACTIVE_USER" -x plank >/dev/null 2>&1 || return 0   # not running: leave it to Plank.desktop

    pkill -u "$ACTIVE_USER" -x plank 2>/dev/null || true
    # A relaunch started before the old DBus name releases just exits again;
    # poll (bounded) until the old process is really gone.
    i=0
    while pgrep -u "$ACTIVE_USER" -x plank >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
        sleep 0.25
        i=$((i + 1))
    done
    # setsid detaches Plank from this handler's session so it survives us exiting.
    su - "$ACTIVE_USER" -c "$SESSION_ENV setsid plank >/dev/null 2>&1 </dev/null &" \
        || log "reanchor_plank: relaunch returned non-zero"
}

# -------------------------------------------------
# Apply lid policy
# -------------------------------------------------
if [ "$LID_STATE" = "open" ]; then
    if [ "$EXTERNAL_CONNECTED" = "yes" ] && [ -n "$INTERNAL" ]; then
        /usr/bin/xrandr \
            --output "$INTERNAL" --auto --pos 0x0 \
            --output "$EXTERNAL" --auto --primary --right-of "$INTERNAL"
        log "lid open: dual display restored"
    elif [ "$EXTERNAL_CONNECTED" = "yes" ]; then
        /usr/bin/xrandr --output "$EXTERNAL" --auto --primary
        log "lid open: external only (no internal panel detected)"
    elif [ -n "$INTERNAL" ]; then
        /usr/bin/xrandr --output "$INTERNAL" --auto --primary
        log "lid open: internal only"
    fi

    # Outputs just moved; re-attach the dock to the new primary.
    reanchor_plank

    # Start xfdashboard if not already running
    if [ -n "$ACTIVE_USER" ] && ! pgrep -u "$ACTIVE_USER" xfdashboard >/dev/null; then
        su - "$ACTIVE_USER" -c "sleep 2; $SESSION_ENV /usr/bin/xfdashboard &"
    fi

else
    # Lid closed
    if [ "$EXTERNAL_CONNECTED" = "yes" ]; then
        if [ -n "$INTERNAL" ]; then
            /usr/bin/xrandr --output "$INTERNAL" --off --output "$EXTERNAL" --auto --primary
        else
            /usr/bin/xrandr --output "$EXTERNAL" --auto --primary
        fi
        log "lid closed: internal off, external primary"
        reanchor_plank
    else
        suspend_system
    fi
fi


exit 0
