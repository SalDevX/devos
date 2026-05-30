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
#   logged; a second run (after enabling the repo) usually clears them. yay one-liner
#   is printed at the end as the easy alternative.
set -uo pipefail

REPO_NAME="devos-local"
FORCE=0; ARGS=()
for a in "$@"; do [[ "$a" == --force ]] && FORCE=1 || ARGS+=("$a"); done
REPO_DIR="${ARGS[0]:-$HOME/devos-local}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LIST="$ROOT/aur-build-list.txt"
echo "[build-aur-repo] list: $LIST"
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

# makepkg's prepare/build/package phases need a real Unix FS (symlinks,
# exec bits) — exFAT raises "Operation not permitted". Packages with an
# epoch (e.g. brave-bin 1:1.90.124-1) also produce filenames containing
# ":" which exFAT refuses with "Invalid argument". Route BOTH the build
# dir AND the package-output dir through /var/tmp, then copy the final
# .pkg.tar.zst into $REPO_DIR with ":" → "_" so the exFAT repo accepts it.
# repo-add reads the real version from PKGINFO inside the package, not
# from the filename, so pacman semantics are preserved.
BUILDDIR_BASE="/var/tmp/devos-makepkg"
PKGDEST_BASE="/var/tmp/devos-makepkg-pkgs"
mkdir -p "$BUILDDIR_BASE" "$PKGDEST_BASE"

ok=0; skip=0; failc=0
while IFS= read -r line; do
  pkg="${line%%#*}"; pkg="${pkg//[[:space:]]/}"
  [[ -z "$pkg" ]] && continue

  # 'local:<path>' builds a repo-local PKGBUILD instead of cloning from the AUR
  # (path relative to the repo root). $name is the real pkgname (drives the repo,
  # idempotency and logs); $localpath is set only for local entries.
  localpath=""; name="$pkg"
  if [[ "$pkg" == local:* ]]; then
    localpath="$ROOT/${pkg#local:}"
    name="$(basename "$localpath")"
  fi

  # idempotent: already in the repo?
  if (( ! FORCE )) && compgen -G "$REPO_DIR/${name}-*.pkg.tar.zst" >/dev/null; then
    echo "-- skip (already built): $name"; printf '%s\n' "$name" >> "$BUILT"; ((skip++)); continue
  fi

  echo "==> building: $name"
  if [[ -n "$localpath" ]]; then
    srcpath="$localpath"
    if [[ ! -f "$srcpath/PKGBUILD" ]]; then
      echo "$(ts)  $name  LOCAL-MISSING" | tee -a "$FAIL_LOG" >/dev/null
      echo "   no PKGBUILD at $srcpath"; ((failc++)); continue
    fi
  else
    srcpath="$SRC/$pkg"
    if [[ -d "$srcpath/.git" ]]; then
      git -C "$srcpath" pull --ff-only >/dev/null 2>&1 || true
    else
      rm -rf "${SRC:?}/$pkg"
      if ! git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$srcpath" >/dev/null 2>&1; then
        echo "$(ts)  $name  CLONE-FAILED" | tee -a "$FAIL_LOG" >/dev/null
        echo "   clone failed"; ((failc++)); continue
      fi
    fi
  fi

  MKPKG_EXTRA=(); (( FORCE )) && MKPKG_EXTRA=(--force --clean)
  # PKGDEST on Unix FS so makepkg can write epoch-colon filenames; SRCDEST too,
  # so a local PKGBUILD's downloaded tarballs never land in the tracked repo.
  # Per-pkg makepkg output goes to $REPO_DIR/build-$name.log (text — exFAT-safe).
  PKGDEST_PKG="$PKGDEST_BASE/$name"
  mkdir -p "$PKGDEST_PKG"
  rm -f "$PKGDEST_PKG"/*.pkg.tar.zst 2>/dev/null || true
  if ( cd "$srcpath" && \
       BUILDDIR="$BUILDDIR_BASE" PKGDEST="$PKGDEST_PKG" SRCDEST="$BUILDDIR_BASE" \
       makepkg -s --noconfirm --needed "${MKPKG_EXTRA[@]}" ) >"$REPO_DIR/build-$name.log" 2>&1; then
    # Copy artifacts to exFAT repo with ":" → "_" in filename so exFAT
    # accepts them. repo-add will rebuild the db from the renamed files.
    copied=0
    for _src in "$PKGDEST_PKG"/*.pkg.tar.zst; do
      [[ -e "$_src" ]] || continue
      _safe="$(basename "$_src" | tr ':' '_')"
      cp "$_src" "$REPO_DIR/$_safe" && copied=$((copied + 1))
    done
    if (( copied > 0 )); then
      echo "$(ts)  $name" >> "$SUCCESS_LOG"; printf '%s\n' "$name" >> "$BUILT"; ((ok++)); echo "   ok ($copied artifact(s))"
      rm -f "$REPO_DIR/build-$name.log"
    else
      echo "$(ts)  $name  NO-ARTIFACT" | tee -a "$FAIL_LOG" >/dev/null; echo "   no artifact (see $REPO_DIR/build-$name.log)"; ((failc++))
    fi
  else
    echo "$(ts)  $name  BUILD-FAILED" | tee -a "$FAIL_LOG" >/dev/null; echo "   build failed (see $REPO_DIR/build-$name.log)"; ((failc++))
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
  yay -S --noconfirm \$(grep -vE '^#|^\$' "${LIST}")
EOF
