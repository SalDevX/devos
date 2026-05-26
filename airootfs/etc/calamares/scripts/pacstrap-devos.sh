#!/usr/bin/env bash
set -euo pipefail

ROOT=/mnt
PKGLIST=/etc/calamares/scripts/packages.install

# Build package array — strip comments, blank lines, and live-only packages
mapfile -t PKGS < <(grep -vE '^\s*#|^\s*$' "$PKGLIST")

echo "[devos] pacstrap: installing ${#PKGS[@]} packages to $ROOT"
pacstrap -K "$ROOT" base linux-lts linux-lts-headers linux-firmware intel-ucode "${PKGS[@]}"
echo "[devos] pacstrap: done"
