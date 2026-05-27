#!/usr/bin/env bash
# Build the DevOS archiso.
#
# Usage: sudo bash devos/tools/build-iso.sh [OUT_DIR]
#
# Work dir: /var/tmp/archiso-work  (real disk, not tmpfs — avoids OOM on /tmp)
# Out dir:  /var/tmp/archiso-out   (or $1 if given)
#
# The work dir is wiped before every run so stale state never carries over.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="/var/tmp/archiso-work"
OUT_DIR="${1:-/var/tmp/archiso-out}"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash devos/tools/build-iso.sh"; exit 1; }

echo "==> Cleaning previous work dir: $WORK_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

echo "==> Building DevOS ISO"
echo "    profile : $PROFILE_DIR"
echo "    work    : $WORK_DIR"
echo "    out     : $OUT_DIR"
echo

mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

echo
echo "==> Done."
ls -lh "$OUT_DIR"/*.iso 2>/dev/null || echo "(no ISO found in $OUT_DIR)"
