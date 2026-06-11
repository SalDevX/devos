#!/usr/bin/env bash
# DevOS scrubber — strips personal data from the shipped skel AND the canonical
# xfce-xml/ panel export so the whole repo is publishable.
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
SKEL_PANEL="$SKEL/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
# Canonical XFCE export in the parent repo — published in git, so scrub it too.
XFCE_XML_PANEL="$(cd "$(dirname "$0")/../.." && pwd)/xfce-xml/xfce4-panel.xml"

echo "scrubbing: $SKEL"

# 1) Rewrite any provided source usernames -> generic 'user'
for u in "${OLD_USERS[@]:-}"; do
  [[ -z "$u" ]] && continue
  grep -rlZ -- "$u" "$SKEL" 2>/dev/null | while IFS= read -r -d '' f; do
    sed -i "s#/home/${u}#/home/user#g; s#\\b${u}\\b#user#g" "$f"
  done || true
done

# 2) XFCE panel: empty systray memory (Wi-Fi SSIDs, app history, favorites) and
#    blank location/identity string fields — by PROPERTY NAME, value-agnostic, so
#    it strips them regardless of contents. Applied to BOTH the shipped skel panel
#    and the canonical xfce-xml export (the latter is published in git).
scrub_panel() {
  local PANEL="$1"
  [[ -f "$PANEL" ]] || return 0
  perl -0777 -i -pe '
    for my $p (qw(known-legacy-items known-items hidden-items hidden-legacy-items recent favorites)) {
      s{<property name="\Q$p\E" type="array">.*?</property>}{<property name="$p" type="array"/>}gs;
    }
  ' "$PANEL"
  for prop in latitude longitude name offset timezone background-image; do
    sed -i "s#\(name=\"${prop}\" type=\"string\" value=\"\)[^\"]*#\1#g" "$PANEL"
  done
  echo "  scrubbed panel: $PANEL"
}
scrub_panel "$SKEL_PANEL"
scrub_panel "$XFCE_XML_PANEL"

echo "scrub complete"
