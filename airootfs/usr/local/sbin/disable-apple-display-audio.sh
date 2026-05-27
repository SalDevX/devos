#!/usr/bin/env bash
# Disable Apple Cinema Display USB audio chip (vendor 05ac, product 1105).
# The udev rule handles this on hotplug; this script covers already-connected devices at boot.
for dev in /sys/bus/usb/devices/*; do
    vid=$(cat "$dev/idVendor" 2>/dev/null)
    pid=$(cat "$dev/idProduct" 2>/dev/null)
    [[ "$vid" == "05ac" && "$pid" == "1105" ]] && echo 0 > "$dev/authorized" || true
done
