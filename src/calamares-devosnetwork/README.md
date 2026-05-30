# devosnetwork — Calamares "connect before you install" view module

A C++/QML Calamares **view module** that is the **first page** of the DevOS
installer. It detects a wired link, lists Wi-Fi networks (auto-refreshed), and
connects via `nmcli` — and is deliberately impossible to get stuck on: a **Skip**
button is always present and always enabled.

## Why C++/QML and not Python

Calamares 3.4 removed the PythonQt UI interface — Python modules are **headless
job modules only** (no UI). A page shown *before* partitioning that talks to
NetworkManager therefore has to be a compiled **`QmlViewStep`** (C++ backend +
QML front-end). Calamares ships **no external module SDK** (no dev headers / CMake
config), so this module is built **in-tree**: the DevOS Calamares package
(`devos/pkgbuilds/calamares`) injects this directory into the Calamares source
tree and rebuilds Calamares from source.

## Files

| File | Role |
|------|------|
| `Config.h` / `Config.cpp` | Backend: `nmcli` via `QProcess`, Wi-Fi list, connection state. Exposed to QML as `config`. |
| `DevosNetworkViewStep.{h,cpp}` | `Calamares::QmlViewStep` subclass. No install jobs; `getConfig()` exposes `Config`. |
| `devosnetwork.qml` | The page UI (Qt6 QtQuick). DevOS palette. |
| `devosnetwork.qrc` | Bundles `devosnetwork.qml` at `:/devosnetwork.qml`. |
| `CMakeLists.txt` | `calamares_add_plugin(... TYPE viewmodule ...)`. **No** `NO_CONFIG` — that would stamp `noconfig: true` into `module.desc` and make Calamares skip the runtime `.conf` (see comment in the file). |

The runtime config is **not** here — it ships in the airootfs at
`/etc/calamares/modules/devosnetwork.conf` so it can be tuned without recompiling.
`module.desc` is **generated** by `calamares_add_plugin`; do not hand-write one.

## How it reaches the ISO

1. `aur-build-list.txt` has `local:pkgbuilds/calamares` (instead of `calamares`).
2. `tools/build-aur-repo.sh` builds that local PKGBUILD; its `prepare()` copies
   this dir to `…/calamares-<ver>/src/modules/devosnetwork`, where
   `src/modules/CMakeLists.txt` auto-discovers and compiles it.
3. The package installs `…/lib/calamares/modules/devosnetwork/` (the `.so` +
   generated `module.desc`) into the squashfs; the `.conf` comes from the airootfs.
4. `settings.conf` lists `devosnetwork` first in the `show:` sequence.

## Behaviour

- **Wired detected** → green "you're online", Next enabled immediately.
- **Wi-Fi** → list with SSID, signal bars, security (WPA2/WPA3/Open); secured
  networks reveal a password field; Connect runs `nmcli device wifi connect`.
  Refreshes every `refreshIntervalMs` (default 5 s).
- **Skip** → always works, logs a warning to the Calamares log, never blocks.
- **Errors** — missing `nmcli` → Skip-only; NetworkManager inactive → one
  `systemctl start` attempt then Skip; wrong password → field cleared, retry;
  connect exceeding `connectTimeoutMs` (default 15 s) → timeout, retry or skip.

## Security notes

- `nmcli` is invoked via `QProcess` with an **argv list — never a shell** — so
  SSIDs/passwords cannot be shell-injected.
- The password is passed as an `nmcli` argument (briefly visible in this
  process's argv to root only); this is inherent to `nmcli`'s CLI and the live
  session is single-user root. The password is never logged.

## Maintenance ⚠️

- **Untestable on the dev host** — needs the full Calamares build environment;
  build and smoke-test it inside the ISO (VM/bare metal).
- **On every Calamares bump**: sync `pkgver` + `sha256sums` in
  `pkgbuilds/calamares/PKGBUILD`, and re-verify the `QmlViewStep` /
  `calamares_add_plugin` API against the new release (this module targets 3.4.2).
- **Rebuilds**: `build-aur-repo.sh` skips a package already in the repo. After
  editing this module, remove the stale `calamares-*.pkg.tar.*` from the local
  repo or run with `--force`, else the change won't be picked up.
