#!/usr/bin/env bash
# Build DevOS AUR packages into a local pacman repo. Fully idempotent.
#
#   Usage: tools/build-aur-repo.sh [REPO_DIR] [--force]
#
#   Reads : aur-build-list.txt (one pkg per line, '#' comments) IN ORDER — so the
#           priority block at the top builds first: brave-bin, xfdashboard,
#           libinput-gestures, ttf-* fonts, shell/terminal tools, then the rest.
#   Writes: $REPO_DIR/devos-local.db.tar.zst  (+ the *.pkg.tar.zst files)
#           $REPO_DIR/build-success.log   $REPO_DIR/build-failed.log
#           $REPO_DIR/devos-aur-built.txt (names — append to packages.x86_64)
#   Needs : base-devel + git; run as a NORMAL user with sudo rights.
#
#   Idempotent: a package already present in the repo is skipped (use --force to
#   rebuild). Source clones are cached under $REPO_DIR/.src and git-pulled on reruns,
#   so re-running only builds what's missing or previously failed.
#
#   NOTE: a plain makepkg loop does not resolve AUR->AUR dependencies. Failures are
#   logged; a second run (after enabling the repo) usually clears them. paru one-liner
#   is printed at the end as the easy alternative.
set -uo pipefail

REPO_NAME="devos-local"
FORCE=0; ARGS=()
for a in "$@"; do [[ "$a" == --force ]] && FORCE=1 || ARGS+=("$a"); done
REPO_DIR="${ARGS[0]:-$HOME/devos-local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/aur-build-list.txt"
SRC="$REPO_DIR/.src"
SUCCESS_LOG="$REPO_DIR/build-success.log"
FAIL_LOG="$REPO_DIR/build-failed.log"
BUILT="$REPO_DIR/devos-aur-built.txt"

[[ $EUID -ne 0 ]] || { echo "Run as a normal user (makepkg refuses root)."; exit 1; }
command -v makepkg >/dev/null || { echo "Install base-devel first."; exit 1; }
command -v git     >/dev/null || { echo "Install git first."; exit 1; }
[[ -f "$LIST" ]] || { echo "Missing $LIST"; exit 1; }
mkdir -p "$REPO_DIR" "$SRC"
: > "$BUILT"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

ok=0; skip=0; failc=0
while IFS= read -r line; do
  pkg="${line%%#*}"; pkg="${pkg//[[:space:]]/}"
  [[ -z "$pkg" ]] && continue

  # idempotent: already in the repo?
  if (( ! FORCE )) && compgen -G "$REPO_DIR/${pkg}-*.pkg.tar.zst" >/dev/null; then
    echo "-- skip (already built): $pkg"; printf '%s\n' "$pkg" >> "$BUILT"; ((skip++)); continue
  fi

  echo "==> building: $pkg"
  if [[ -d "$SRC/$pkg/.git" ]]; then
    git -C "$SRC/$pkg" pull --ff-only >/dev/null 2>&1 || true
  else
    rm -rf "${SRC:?}/$pkg"
    if ! git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$SRC/$pkg" >/dev/null 2>&1; then
      echo "$(ts)  $pkg  CLONE-FAILED" | tee -a "$FAIL_LOG" >/dev/null
      echo "   clone failed"; ((failc++)); continue
    fi
  fi

  if ( cd "$SRC/$pkg" && makepkg -s --noconfirm --needed ) >/dev/null 2>&1; then
    if cp "$SRC/$pkg"/*.pkg.tar.zst "$REPO_DIR"/ 2>/dev/null; then
      echo "$(ts)  $pkg" >> "$SUCCESS_LOG"; printf '%s\n' "$pkg" >> "$BUILT"; ((ok++)); echo "   ok"
    else
      echo "$(ts)  $pkg  NO-ARTIFACT" | tee -a "$FAIL_LOG" >/dev/null; echo "   no artifact"; ((failc++))
    fi
  else
    echo "$(ts)  $pkg  BUILD-FAILED" | tee -a "$FAIL_LOG" >/dev/null; echo "   build failed"; ((failc++))
  fi
done < "$LIST"

# (re)build the repo database from everything collected so far
( cd "$REPO_DIR" && repo-add -q "${REPO_NAME}.db.tar.zst" ./*.pkg.tar.zst >/dev/null 2>&1 ) || true

echo
echo "built=$ok  skipped=$skip  failed=$failc    repo: $REPO_DIR"
echo "success: $SUCCESS_LOG    failures: $FAIL_LOG"
cat <<EOF

Next:
  1) Enable the repo in devos/pacman.conf (above [core]):
       [${REPO_NAME}]
       SigLevel = Optional TrustAll
       Server = file://${REPO_DIR}
  2) Add built names to the ISO list:   cat "${BUILT}" >> "${ROOT}/packages.x86_64"
  3) Re-run to retry failures (built packages are skipped automatically).

AUR deps not resolving in the loop? Easy path:
  paru -S --noconfirm \$(grep -vE '^#|^\$' "${LIST}")
EOF
