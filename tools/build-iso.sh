#!/usr/bin/env bash
# Build the DevOS archiso.
#
# Usage: sudo bash devos/tools/build-iso.sh [OUT_DIR]
#
# Work dir: /var/tmp/archiso-work  (real disk, not tmpfs — avoids OOM on /tmp)
# Out dir:  /run/media/craftworkson/space2/archiso-out  (or $1 if given)
#
# Storage: the "space2" external drive is the sole source of truth.
#   - devos-local (AUR repo)  → /run/media/craftworkson/space2/devos-local
#   - archiso-out (ISO output) → /run/media/craftworkson/space2/archiso-out
# pacman download cache uses mkarchiso's default (per-build chroot cache inside
# WORK_DIR, wiped between runs). /mnt/storage is NOT used by this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="/var/tmp/archiso-work"
DEVOS_LOCAL="/run/media/craftworkson/space2/devos-local"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash devos/tools/build-iso.sh"; exit 1; }

# ---------------------------------------------------------------------------
# Sanity-check the devos-local repo exists. pacman.conf hardcodes the same
# path (Server = file:///run/media/craftworkson/space2/devos-local), so if the
# space2 drive isn't mounted we fail fast with a clear message.
# ---------------------------------------------------------------------------
if [[ ! -e "$DEVOS_LOCAL/devos-local.db" ]]; then
    echo "ERROR: devos-local.db not found at $DEVOS_LOCAL" >&2
    echo "  Mount the space2 external drive, then rerun." >&2
    echo "  Build the repo if missing: bash devos/tools/build-aur-repo.sh $DEVOS_LOCAL" >&2
    exit 1
fi

echo "==> devos-local: $DEVOS_LOCAL"

OUT_DIR="${1:-/run/media/craftworkson/space2/archiso-out}"
mkdir -p "$OUT_DIR"

echo "==> Cleaning previous work dir: $WORK_DIR"
rm -rf "$WORK_DIR"

# ---------------------------------------------------------------------------
# Merge AUR-built package names into packages.x86_64 so mkarchiso installs
# them from [devos-local]. build-aur-repo.sh produces devos-aur-built.txt
# but that file can drift (entries appended on "skip-already-built" detection
# are never removed when the .pkg.tar.zst is later deleted). The repo db can
# also list phantoms. Filter against actual on-disk artifacts so mkarchiso
# never asks pacman for a file the repo can't serve. Restore the original
# packages.x86_64 on exit via trap (covers success + failure paths).
# ---------------------------------------------------------------------------
PACKAGES_FILE="$PROFILE_DIR/packages.x86_64"
AUR_BUILT="$DEVOS_LOCAL/devos-aur-built.txt"
PACKAGES_BACKUP="$(mktemp -t devos-packages.XXXXXX)"
FILTERED_BUILT="$(mktemp -t devos-built-filtered.XXXXXX)"
cp "$PACKAGES_FILE" "$PACKAGES_BACKUP"
trap 'cp "$PACKAGES_BACKUP" "$PACKAGES_FILE"; rm -f "$PACKAGES_BACKUP" "$FILTERED_BUILT"' EXIT

if [[ -f "$AUR_BUILT" ]]; then
    phantom=()
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if compgen -G "$DEVOS_LOCAL/${pkg}-*.pkg.tar.zst" >/dev/null; then
            printf '%s\n' "$pkg" >> "$FILTERED_BUILT"
        else
            phantom+=("$pkg")
        fi
    done < "$AUR_BUILT"

    if (( ${#phantom[@]} > 0 )); then
        echo "WARNING: ${#phantom[@]} entries in $AUR_BUILT have no .pkg.tar.zst on disk:" >&2
        printf '    %s\n' "${phantom[@]}" >&2
        echo "    These will be skipped. Heal by rerunning:" >&2
        echo "      bash devos/tools/build-aur-repo.sh $DEVOS_LOCAL" >&2
        echo "    (idempotent — only rebuilds what's missing)" >&2
    fi

    new_count=$(grep -vxFf "$PACKAGES_BACKUP" "$FILTERED_BUILT" 2>/dev/null | grep -cv '^[[:space:]]*$' || true)
    {
        printf '\n# --- AUR packages (auto-appended by build-iso.sh from %s) ---\n' "$AUR_BUILT"
        grep -vxFf "$PACKAGES_BACKUP" "$FILTERED_BUILT"
    } >> "$PACKAGES_FILE"
    echo "==> AUR pkg names merged into packages.x86_64: $new_count new entries (on-disk verified)"
else
    echo "WARNING: $AUR_BUILT not found." >&2
    echo "         AUR pkgs (calamares, yay, brave-bin, ...) will be ABSENT from the ISO." >&2
    echo "         Run: bash devos/tools/build-aur-repo.sh $DEVOS_LOCAL" >&2
fi

echo "==> Building DevOS ISO"
echo "    profile : $PROFILE_DIR"
echo "    work    : $WORK_DIR"
echo "    out     : $OUT_DIR"
echo

mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

echo
echo "==> Done."
ls -lh "$OUT_DIR"/*.iso 2>/dev/null || echo "(no ISO found in $OUT_DIR)"
