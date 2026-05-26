#!/usr/bin/env bash
set -euo pipefail

ROOT=/mnt

# Remove live-only installer shortcut from installed skel and any home dirs
rm -f "$ROOT/etc/skel/Desktop/install-devos.desktop"
find "$ROOT/home" -name "install-devos.desktop" -delete 2>/dev/null || true

# Remove calamares config from installed system (live-only)
rm -rf "$ROOT/etc/calamares"

echo "[devos] cleanup done"
