#!/usr/bin/env bash
# DevOS skel scrubber — strips personal data so the dotfiles are publishable.
# Idempotent; safe to re-run. No personal values are hardcoded in this script.
#
#   Usage: tools/scrub.sh [SKEL_DIR] [OLD_USER ...]
#
# Pass the source username(s) to rewrite their /home paths and bare names to 'user'.
# The XFCE panel/weather scrub blanks fields by PROPERTY NAME (value-agnostic), so it
# removes saved Wi-Fi SSIDs, app history, and location regardless of their contents.
set -eu

SKEL="${1:-$(cd "$(dirname "$0")/.." && pwd)/airootfs/etc/skel}"
shift || true
OLD_USERS=("$@")
PANEL="$SKEL/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

echo "scrubbing: $SKEL"

# 1) Rewrite any provided source usernames -> generic 'user'
for u in "${OLD_USERS[@]:-}"; do
  [[ -z "$u" ]] && continue
  grep -rlZ -- "$u" "$SKEL" 2>/dev/null | while IFS= read -r -d '' f; do
    sed -i "s#/home/${u}#/home/user#g; s#\\b${u}\\b#user#g" "$f"
  done || true
done

# 2) XFCE panel: empty systray memory (Wi-Fi SSIDs, app history, favorites)...
if [[ -f "$PANEL" ]]; then
  perl -0777 -i -pe '
    for my $p (qw(known-legacy-items known-items hidden-items hidden-legacy-items recent favorites)) {
      s{<property name="\Q$p\E" type="array">.*?</property>}{<property name="$p" type="array"/>}gs;
    }
  ' "$PANEL"
  # ...and blank location/identity string fields by property name (value-agnostic)
  for prop in latitude longitude name offset timezone background-image; do
    sed -i "s#\(name=\"${prop}\" type=\"string\" value=\"\)[^\"]*#\1#g" "$PANEL"
  done
fi

echo "scrub complete"
