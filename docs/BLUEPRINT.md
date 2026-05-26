# DevOS Blueprint — Golden-State Capture of `workstation`

Captured: 2026-05-26 · Source host: `workstation` · Base: Arch Linux (rolling) · Arch: x86_64
Hardware: Apple MacBook (Intel Haswell "Crystal Well", `i915`, Broadcom Wi-Fi, Magic Trackpad/Mouse)

> This document is the blueprint for building **DevOS**, a custom Arch-based ISO that
> reproduces this machine's full stack. Raw captures live alongside this file in
> `~/devos-blueprint/` (package lists, xfconf dumps, copied dotfiles, copied unit files,
> xorg configs, and the canonical XFCE perchannel XMLs).

## Corrections applied (2026-05-26) — DevOS scope

The capture below describes the **source machine** (host `workstation`), a hybrid box. Per
project decisions it splits into two distros; DevOS takes only the developer half:

| Topic | DevOS (`devos/` profile) | MusicOS (separate project) |
|---|---|---|
| Default session | **XFCE** | dwm |
| Kernel | `linux-lts` | `linux-rt` / `linux-rt-lts` |
| Browser | **Brave stable** (`brave-bin`), config dir `…/Brave-Browser` | n/a |
| Audio/DAW | excluded (see `audio-packages-review.txt`) | JACK/LV2/`daw.target` |

- **Boot:** systemd-boot (confirmed). Template in `devos/installer/loader/`. Source root
  `PARTUUID=YOUR-PARTUUID-HERE` is **scrubbed** to `YOUR-PARTUUID-HERE`; `install.sh` auto-fills
  the real value from the mounted target at install time.
- **Login:** no display manager, **no greeter** (`arcade-greeter` dropped). Pure
  TTY → `startx` → XFCE, with optional `getty` autologin for a single user.
- **Scrub:** `/home/user` → `/home/user`, PARTUUID, Wi-Fi SSIDs removed,
  `~/.zshenv.secret` excluded. Applied by `devos/tools/scrub.sh`.

A buildable archiso profile implementing the above lives in **`devos/`** (see its README).
Sections 1–8 below are the original full-machine capture; read them through this lens
(e.g. §0's RT kernels and §1's audio stack belong to MusicOS).

---

## 0. System identity (the shape of the target)

| Layer | Value |
|---|---|
| Distro | Arch Linux, `BUILD_ID=rolling` |
| Kernels (explicit) | `linux-lts`, `linux-rt`, `linux-rt-lts` (+ headers), **no mainline `linux`** |
| Running kernel | `6.18.32-2-lts` (DKMS built for `6.18.33-1-lts`, `6.12.91-rt18…-rt-lts`, `7.0.10…-rt`) |
| Microcode | `intel-ucode` |
| Bootloader | ESP at `/boot` (vfat, `umask=077`, root-only) — likely **systemd-boot**; confirm with sudo |
| Filesystems | `/`=ext4 (sda2), `/boot`=vfat ESP (sda1), `/home`=ext4 (sda3), `/tmp`=tmpfs 6G, `/swapfile` swap |
| Init/initramfs | `mkinitcpio`, `HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)` |
| Locale / console | `LANG=en_US.UTF-8`, console `FONT=ter-132b` (HiDPI terminus) |
| Repos | `core`, `extra`, `multilib` (standard; no custom repos in pacman.conf) |
| Display server | Xorg (no Wayland compositor as primary); `intel` DDX with TearFree, DRI3 |
| Display manager | **none** — boots to TTY, `startx` → `.xinitrc` (custom greeter present, see §6) |
| Primary session | **dwm** (`/usr/local/bin/dwm`); XFCE is the alternate session |
| Audio | PipeWire (user units) + JACK2 + PulseAudio compat — pro-audio stack |
| User groups | `realtime docker ollama video uucp render input disk audio wheel focus shared` |
| Other users | `reaper` (DAW), `testuser1` referenced — multi-user box |

---

## 1. Package manifest

Authoritative lists (use these for the ISO):
- `pacman-explicit.txt` — **648** explicitly installed (`pacman -Qqe`)
- `aur-packages.txt` — **162** foreign/AUR (`pacman -Qqm`)
- `packages-repo.txt` — **549** repo-only (explicit minus AUR) → **candidate `packages.x86_64`**

> AUR/foreign packages cannot go in archiso's `packages.x86_64` directly — they must be
> prebuilt into a custom local repo (see §7). DKMS packages need headers for every kernel.

### Categorized by purpose (representative members; full set in the txt files)

**Base / boot / system**
`base`, `base-devel`, `linux-lts`(+headers), `linux-rt`(+headers), `linux-rt-lts`(+headers),
`linux-firmware`, `intel-ucode`, `dkms`, `grub`, `efibootmgr`, `dosfstools`, `mokutil`, `fwupd`,
`reflector`, `pacman-contrib`, `pkgfile`, `plocate`, `archiso`, `arch-install-scripts`, `timeshift`

**Apple / MacBook hardware enablement**
`broadcom-wl-dkms` (Wi-Fi), `mbpfan` (fans), `hfsprogs` (HFS+), `bluez-hid2hci`, `bluez-utils`,
`xf86-video-intel`, `intel-media-driver`, `libva-intel-driver`, `vulkan-intel`, `intel-gpu-tools`
+ DKMS: `facetimehd` (webcam), `hid-magicmouse`, `ch34x`, `v4l2loopback`/`v4l2loopback-dc`

**Xorg**
`xorg-server`, full `xorg-*` apps/util suite, `xorg-xinit`, `xf86-input-libinput`/`-evdev`/`-void`

**Window managers / desktop shells** (multi-WM box)
Primary: `dwm` (built from source — *not* a package, see §6), `dwm-systray`(AUR)
XFCE suite: `xfce4-session`, `xfwm4`, `xfdesktop`, `xfce4-panel` + ~30 `xfce4-*` plugins,
`xfdashboard`(AUR), `xfwm4-themes`
Also installed: `i3-wm`, `i3status`, `openbox`, `komorebi`(AUR), `polybar`, `waybar`, `sxhkd`,
`autotiling`, `rofi`(+`-calc`/`-emoji`), `dmenu`, `wofi`, `picom`(+`picom-jonaburg-git`), `plank`,
`conky`, `devilspie2`, `touchegg`, `wmctrl`, `xdotool`, `xbindkeys`, `xcape`

**Pro audio / DAW** (the defining workload)
DAWs/hosts: `ardour`, `reaper`, `carla`, `qtractor`-class hosts, `guitarix`, `rakarrack-plus`
Servers/routing: `jack2`, `jack2-dbus`, `jack-example-tools`, `jack_mixer`, `patchmatrix`,
`patchance`(AUR), `qpwgraph`, `qjackctl`, `pipewire-alsa`, `pulseaudio`(+`-alsa`/`-jack`/`-equalizer`),
`wireplumber`, `libffado`, `realtime-privileges`, `rtirq`, `rt-tests`, `schedtool`
Synths/instruments: `zynaddsubfx`, `amsynth`(+vst/lv2), `yoshimi-lv2`, `vmpk`, `setbfree-lv2`,
`padthv1`/`samplv1`/`synthv1`/`drumkv1`-lv2, `odin2`/`vaporizer2`/`ob-xd`-lv2
Effects: dozens of LV2 — `calf`, `x42-plugins-lv2`, `zam-plugins-lv2`, `dragonfly-reverb`,
`neural-amp-modeler-lv2-git`(AUR), `drumgizmo-lv2`, `noise-repellent`, `eq10q`, `infamousplugins`, …
Windows-VST bridge: `yabridge-bin`(AUR); Focusrite control: `alsa-scarlett-gui`

**Dev languages & toolchains**
`go`, `ruby`, `clojure`, `dotnet-sdk`, `mono`, `jdk17-openjdk`, `python312`, `npm`/`nvm`/`yarn`,
`uv`, `pyenv`, `cmake`, `meson`, `gdb`, `ctags`, `tree-sitter-cli`, `git`(+`-lfs`/`-filter-repo`),
`github-cli`, `gemini-cli`, `arduino-cli`/`arduino-language-server`, `platformio-git`(AUR),
`qtcreator`, `neovim`, `vim`, `helix`, `visual-studio-code-bin`(AUR), `pybind11`, Rust via `rustup` (~/.cargo, not pacman)

**Containers / VM / cloud**
`qemu-desktop`, `minikube`, `flyctl-bin`(AUR), `cloudflared`, `rclone`, Docker (user in `docker` group)

**Browsers**: `brave-nightly-bin`(AUR), `chromium`, `firefox`, `netsurf`, `vieb`(AUR), `torbrowser-launcher`

**Security / networking**
`nmap`, `aircrack-ng`, `arp-scan`, `tcpdump`, `wireshark-qt`, `macchanger`, `proxychains-ng`,
`torsocks`, `firejail`, `clamav`, `rkhunter`, `fail2ban`, `ufw`, `iptables`, `wireguard-tools`,
`networkmanager`(+`-openvpn`), `nethogs`/`iftop`/`bmon`/`nload`, `mtr`, `sshfs`, `samba`, `remmina`,
`tigervnc`, `proxychains` (plus pip: `airdrop-ng`, `airgraph-ng`)

**Terminals**: `alacritty`, `kitty`, `xfce4-terminal`, `yakuake`
**Shell/CLI UX**: `zsh`(+`-autosuggestions`/`-syntax-highlighting`/`powerlevel10k`), `tmux`, `fzf`,
`direnv`, `eza`, `bat`, `fd`, `ripgrep`, `yazi`, `ncdu`, `fastfetch`/`neofetch`, `lolcat`, `glow`, `mdcat`

**Fonts / theming**
Nerd fonts (`ttf-firacode-nerd`, `ttf-jetbrains-mono-nerd`, `ttf-hack-nerd`, `ttf-ubuntu-nerd`),
`terminus-font`, `noto-fonts`(+`-emoji`), `ttf-ms-fonts`, `ttf-dejavu`;
`arc-gtk-theme`, `papirus`/`oranchelo`/`moka`/`faba`/`gruvbox-plus` icon themes,
`mcos-mjv-xfce-edition`(AUR, macOS-like), `lxappearance`, `qt5ct`, `qt5-styleplugins`

**Creative / productivity**
`libreoffice-still`, `calibre`, `obsidian`, `typora`(AUR), `thunderbird`, `protonmail-bridge`,
`gimp`, `inkscape`, `scribus`, `mpv`, `obs-studio`, `pdfarranger`, `masterpdfeditor-free`(AUR),
`ocrmypdf`, `tesseract-data-eng`/`-ind` (Blender & FreeCAD run from `~/Applications` / AppImages)

---

## 2. Dev stack versions

| Tool | Version / detail |
|---|---|
| Node | `v20.20.2` |
| npm | `11.14.1` (global prefix adds `~/.npm-global/bin`) |
| npm globals | `@google/gemini-cli`, `@vscode/vsce`, `node-gyp`, `nopt`, `playwright`, `semver`, `svgo`, `yarn` |
| Python | `3.14.5` (system); `PYTHONPATH=/usr/lib/python3.14/site-packages` (set globally in `/etc/environment`) |
| pip | huge system-wide set incl. `torch 2.10.0` + CUDA wheels, JupyterLab, FastAPI, `faster-whisper`, `openai-whisper`, audio (`JACK-Client`, `pyliblo3`), `graphifyy 0.7.2`; editable: `context-router` (`~/dev/context-router`) |
| Neovim | `v0.12.2`, LuaJIT 2.1 — config is a **git repo** at `~/.config/nvim` (kickstart-based, `init.lua` 41 KB, native `vim.pack` lockfile) |
| Shells | `bash` ✓, `zsh` ✓ (login shell, p10k), **`fish` not installed** |
| Editors/IDEs | VS Code, Neovim, Vim, Helix, Qt Creator |
| Rust | via `rustup` (`~/.cargo/env` sourced in `.zshenv`) — not a pacman package |

> Note: `python` is system 3.14 with a very large global site-packages. For DevOS, decide whether to
> reproduce the global Python (fragile, externally-managed) or ship a lean base and let users opt in
> via `uv`/`pyenv`/venvs. Recommend the latter.

---

## 3. Config inventory (location → purpose)

### Dotfiles (copied into `dotfiles/`)
| Path | Purpose / notable contents |
|---|---|
| `~/.zshenv` | **Loaded for every zsh.** XDG base dirs, dedup `path=(…)` build (`~/go/bin`, `~/bin`, `~/.local/bin`, `~/.cargo/bin`, `~/.npm-global/bin`, gem bin, `/usr/local/{s,}bin`…), `EDITOR/VISUAL=nvim`, `GPG_TTY`, `LADSPA_PATH`, `XAUTHORITY`, `REGISTRATION_CODE`, sources `~/.zshenv.secret` (secrets — **not captured**) |
| `~/.zshrc` | Interactive: p10k instant prompt + theme, autosuggestions + syntax-highlighting (Arch pkgs), gruvbox highlight styles, fzf (`^R`), direnv hook, ESC-ESC sudo widget, copypath/copybuffer, `zcd`/`z` (yazi), `web` (brave), aliases incl. `X='SESSION=xfce startx'`/`D='SESSION=dwm startx'`, DAW & QEMU helpers |
| `~/.bashrc` | Minimal; TTY neofetch; `X`/`D` startx aliases; PATH adds `~/.local/bin`, `~/.npm-global/bin` |
| `~/.profile` | Essentially empty (all real env in `.zshenv`) |
| `~/.xinitrc` | Sets `XDG_SESSION_TYPE=x11`, `XDG_CURRENT_DESKTOP=XFCE`; `xrandr --output eDP-1 --mode 1680x1050 --rate 60 --primary`; `exec` **dwm** (default) or `startxfce4` based on `$SESSION` |
| `~/.config/picom.conf` | `xrender` backend, vsync, `corner-radius=10` (excl. `Xfce4-panel`), shadows/fading off, `use-damage` |
| `~/.config/libinput-gestures.conf` | 4-finger swipe up → `xfdashboard -t`; swipe l/r 4 → workspace; pinch → ctrl±; (see §5 gestures) |
| `~/.config/brave-flags.conf` | Stable/beta Brave: **enables** gpu-rasterization/zero-copy/native-gpu-buffers, `--disable-gpu-compositing` |
| `~/.config/brave-nightly-flags.conf` | **Active** (installed pkg is `brave-nightly-bin`): `--disable-gpu-rasterization`, `--disable-zero-copy` — **the crash-on-paste fix for Haswell+Mesa** |
| `~/.config/alacritty/alacritty.toml` | Menlo 10.5, `decorations=None`, 100k scrollback, shell `zsh -c tmux`, `opacity=8.0` (⚠ out of 0–1 range → clamps opaque; likely meant `0.8`) |
| `~/.p10k.zsh` | Powerlevel10k theme (9.5 KB) |

### System configs
| Path | Purpose |
|---|---|
| `/etc/mkinitcpio.conf` | HOOKS line above; `MODULES=()`, `FILES=()`, `BINARIES=()` (all defaults) |
| `/etc/environment` | `XDG_DESKTOP_PORTAL=xdg-desktop-portal-xapp`, `LIBVA_DRIVER_NAME=i965`, `PYTHONPATH=…3.14/site-packages` |
| `/etc/X11/xorg.conf.d/00-keyboard.conf` | XkbLayout `us`, model `pc105` |
| `…/10-intel.conf` + `modsettings` | `intel` DDX, `TearFree true`, `DRI 3` (⚠ two Device sections — dedupe) |
| `…/40-libinput.conf` | MacBook `bcm5974` touchpad: tap-to-click, natural scroll, clickfinger, adaptive accel, disable-while-typing |
| `…/50-magicmouse.conf` | Apple Magic Mouse 2: twofinger scroll, natural scrolling |
| `…/99-disable-virtual-keyboard.conf` | `void` driver to kill a phantom virtual keyboard |

### XFCE settings (canonical source copied to `xfce-xml/` — 27 perchannel XMLs)
`xfce-xml/*.xml` are the real settings files (prefer these over the `xfconf-*.txt` dumps for replication):
`xfwm4.xml`, `xfce4-panel.xml`, `xfce4-desktop.xml`, `xfdashboard.xml`, `xfce4-keyboard-shortcuts.xml`,
`xsettings.xml`, `keyboards.xml`, `pointers.xml`, `displays.xml`, `thunar.xml`, `xfce4-terminal.xml`, … (see dir).

---

## 4. XFCE golden settings (exact values to replicate)

> Applies to the **XFCE session only** (`SESSION=xfce`). Replicate by shipping `xfce-xml/*.xml` into
> the skel at `~/.config/xfce4/xfconf/xfce-perchannel-xml/`. Strip personal data first (see §6).

**`xfwm4`** (window manager)
- `theme=Default`, `button_layout=O|SHMC`, `title_font=Sans Bold 9`, `title_alignment=center`
- `click_to_focus=true`, `focus_new=true`, `prevent_focus_stealing=true`, `raise_on_click=false`
- `use_compositing=false` (picom is the compositor instead), `vblank_mode=glx`
- `easy_click=Mod3`, `double_click_action=maximize`, `placement_mode=center`
- `borderless_maximize=true`, `titleless_maximize=true`, `tile_on_move=true`, `snap_to_border/windows=true`
- `zoom_desktop=true`, `zoom_pointer=true`, `workspace_count=3`

**`xfce4-panel`** (single panel `panel-1`)
- `dark-mode=true`, top panel `position=p=6;x=2960;y=11`, `size=20`, `length=100%`, `enable-struts=true`, `position-locked=true`
- `background-style=1`, `background-image=file:///home/user/bitmap.svg` (⚠ user path — ship asset + rewrite)
- Plugin chain (38 plugins): whiskermenu (`button-icon=archlinux-logo`, `menu 1680×959`, `opacity=76`),
  systray, appmenu (global menu), pager, tasklist, pulseaudio, weather, two clocks, fsguard×2, timer,
  separators, and several `launcher` plugins referencing `*.desktop` IDs
- ⚠ Contains **personal data**: weather location *[location redacted]*; clock TZ *[tz redacted]*; a long
  `known-legacy-items` list of saved **Wi-Fi SSIDs** — scrub before publishing.

**`xfce4-desktop`**
- Wallpapers from `~/Media/Images/Wallpaper-Bank/wallpapers/` (sacred-geometry set) — ship a default + rewrite paths
- `single-workspace-mode=true`; desktop icons `icon-size=54`, `single-click=true`, `font=Noto Sans 10`

**`xfdashboard`** (GNOME-overview-like)
- `theme=xfdashboard-dark`, `enable-animations=false`, hot-corner enabled (`activation-corner=1`)
- plugins: `gnome-shell-search-provider`, `middle-click-window-close`; `switch-to-view-on-resume=builtin.windows`

---

## 5. Autostart chain (what launches what, in order)

```
┌ Power on
│
├─ systemd (enabled system services — the "always on" base)
│   networking: NetworkManager(+wait-online,+dispatcher), systemd-resolved, systemd-timesyncd, sshd
│   security:   ufw, iptables, fail2ban
│   hardware:   acpid, upower, thermald, tlp, mbpfan, fancontrol, lm_sensors, cpupower(+performance), irqbalance
│   misc:       cups, cronie, dbus-broker, accounts-daemon, rc-local, getty@ (autologin TTY?)
│   custom:     disable-apple-display-audio, disable-usb-autosuspend, disable-wakeup-user,
│               snd-usb-audio, hugepages, pin-audio-irqs, pin-thunderbolt-irq, pin-system-irqs
│
├─ Login: NO display manager → TTY → (custom greeter, see §6) → startx → ~/.xinitrc
│   ~/.xinitrc: export XDG/session vars → xrandr eDP-1 1680x1050@60 → exec $SESSION
│       SESSION=dwm   (DEFAULT) → exec /usr/local/bin/dwm   [+ slstatus status bar]
│       SESSION=xfce            → exec startxfce4
│
├─ User systemd units (…/systemd/user, graphical-session.target):
│   libinput-gestures, appmenu-gtk-module, gnome-keyring-daemon(+socket), magicmouse,
│   battery-alert.timer, xdg-user-dirs, speech-dispatcher.socket, p11-kit-server.socket
│   AUDIO: pipewire(.socket), pipewire-pulse(.socket), wireplumber, focusrite-jack
│   (also present/odd: test.service ← cruft; plasma-*, syncthing — review)
│
└─ XFCE session only — ~/.config/autostart/*.desktop (OnlyShowIn=XFCE):
    ACTIVE: picom (composit.desktop, `picom --config ~/.config/picom.conf -b`), dunst (Notification),
            plank (dock), pulseaudio --start, libinput-gestures-setup start, xfce4-clipman,
            xfce4-notes, xfdashboard daemon (xfdashboard-startup.sh → `xfdashboard -d`),
            appmenu-registrar, thunar --daemon, xbindkeys, xfsettingsd,
            Proton Mail Bridge (--no-window), start-cronie (sudo …enable --now cronie),
            ufw (sudo ufw enable), ccache/check_clean_caches (cache purgers)
    DISABLED (Hidden=true): blueman, easyeffects(×2), devilspie2, picom.desktop, remmina-applet,
            xfce4-notifyd, xfce4-screensaver, org.xfce.xfdashboard-autostart
```

**libinput gestures** (4-finger driven, via `xdotool`/`xfdashboard`):
- swipe up (4) → `xfdashboard -t` (overview toggle)
- swipe down (4) → `xdotool key ctrl+alt+d` (show desktop)
- swipe left/right (4) → `ctrl+alt+Right`/`Left` (workspace switch)
- swipe left/right (any) → browser fwd/back; swipe down (any) → `_internal ws_down`
- pinch in/out → `ctrl+minus`/`ctrl+plus` (zoom)

**DAW mode** (custom systemd target): `daw-prep.service` (`WantedBy=daw.target`) runs `/usr/local/bin/daw-prep.sh`:
`rfkill block wifi/bluetooth`, `swapoff -a`, reset zram, pin `snd_hda_intel` IRQs→CPU2 and `xhci_hcd`→CPU3.
`daw.target` **conflicts with** NetworkManager/bluetooth/pulseaudio/pipewire/wireplumber (full isolation
for low-latency tracking). Triggered via the `/usr/local/bin/daw` helper. This is a signature DevOS feature.

---

## 5.5 Custom engineering: clamshell display switching (acpid) — CAPTURE VERBATIM

Bespoke laptop-lid logic, **not** replaceable by any default. `systemd-logind` is
explicitly disabled for the lid (`/etc/systemd/logind.conf`): `HandleLidSwitch=ignore`,
`HandleLidSwitchExternalPower=ignore`, `HandleLidSwitchDocked=ignore`,
`HandlePowerKey=ignore` → **acpid owns the lid.**

Wiring: `/etc/acpi/events/lid` (`event=button/lid.*`) → `/etc/acpi/actions/lid.handler.sh`.
(A catch-all `/etc/acpi/events/anything` → `/etc/acpi/handler.sh %e` only logs.)

`lid.handler.sh` policy (`INTERNAL=eDP1`, `EXTERNAL=DP2`, modes `1680x1050` /
`2560x1440@60`; full script at `system/acpi/actions/lid.handler.sh`):

| Lid | External DP2 | Action |
|-----|--------------|--------|
| open | connected | dual: `eDP1`@0x0 + `DP2` right-of, DP2 primary; relaunch xfdashboard |
| open | absent | internal only (`eDP1` primary); relaunch xfdashboard |
| **closed** | **connected** | **`eDP1 --off`** (GPU stops driving hidden panel) + DP2 primary — clamshell |
| **closed** | **absent** | **`systemctl suspend`** |

Verbatim robustness: detects the active **tty1** user via `who` and exports `DISPLAY=:0`
+ that user's `XAUTHORITY` (multi-user safe); probes `xrandr --query | grep '^DP2 connected'`;
debounces duplicate events via `/run/lid-handler.state`; logs to `/var/log/lid-handler.log`.

Companion `disable-wakeup.service` (oneshot, `Before=sleep.target`) writes `XHC1`/`LID0`
to `/proc/acpi/wakeup` so USB/lid don't spuriously wake the machine from suspend.

Archived-but-inactive variants (older/DAW): `lid.sh` (hardcoded user, no detect),
`lid.handler.backup` (no xfdashboard relaunch), `lid.reaper.sh` & `lid.sh.reaper`
(audio user, `xset dpms` blank → MusicOS, in `musicos/acpi/`).

**DevOS integration (done):** active `lid.handler.sh` + `handler.sh` + `events/` →
`devos/airootfs/etc/acpi/`; logind drop-in `…/logind.conf.d/10-devos-lid.conf`;
`disable-wakeup.service` enabled; `acpid` enabled in `customize_airootfs.sh`.
⚠ Output names `eDP1`/`DP2` and ACPI nodes `XHC1`/`LID0` are **hardware-specific** —
adjust per machine via `xrandr` and `cat /proc/acpi/wakeup`.

---

## 6. Missing pieces (manual steps — NOT reproducible from packages alone)

These must be vendored into the DevOS repo as files; they don't come from any pacman/AUR package:

1. **dwm binary + source** — `/usr/local/bin/dwm` is a locally-compiled ELF. Source found at
   `~/dwm-config/dwm-6.5`. → Vendor the patched source + `config.h`; build during ISO or ship binary.
2. **suckless `slstatus`** — `/usr/local/bin/slstatus` (dwm status bar), also locally built. Vendor source.
3. **Custom login greeter** — there is **no display manager**. A bespoke greeter exists:
   `arcade-greeter.service` + `/usr/local/bin/{greeter.sh, arcade-greeter.sh, arcade-login.sh,
   greeter-pam.py, pam-login.py, dimension-greter.sh}`. → Reverse-engineer the boot→login→startx flow
   (likely getty autologin → greeter → `startx`). Decide DevOS default (greeter vs. `ly`/`lightdm`).
4. **Custom `/usr/local/bin` toolkit (~60 items)** — DAW (`daw`, `daw-prep.sh`, `carla-RT`, `patchance-rt`,
   `brave-rt`, `reaper15`, `jack_volume`, `ZLEQ`, `byod`, `rtmon`/`trmon`, `cpu-performance*.sh`,
   `pin-system-irqs.sh`), security (`block_malicious_ips.sh`, `dsniff`, `sniff`, `chromium`→firejail),
   utilities (`clean_caches`, `cleanup_pacman_yay`, `xwinwrap`, `custom-neofetch.sh`). Only the three
   text scripts were copied to `system/local-bin/`; the rest (and binaries) need deliberate vendoring.
5. **Custom systemd units** — copied to `system/systemd/` (17 system) and `system/systemd-user/`.
   Includes `daw-prep`, `daw-stop-upower`, `pin-*`, `disable-*`, `hugepages`, `snd-usb-audio`,
   `cpupower-performance`, `ardour`, `penpot`, `arcade-greeter`, `rc-local`, `ayatana-bamf`. Note the
   referenced **`daw.target`** unit itself was not in the top-level dir — locate and add it.
6. **AUR packages (162)** — need an AUR helper (`paru-bin`/`yay`) and a prebuilt **custom local repo**
   for archiso. Includes `brave-nightly-bin`, `visual-studio-code-bin`, `dwm-systray`, `xfdashboard`,
   `komorebi`, `mbpfan`, `yabridge-bin`, `neural-amp-modeler-lv2-git`, `mcos-mjv-xfce-edition`, etc.
   Many `*-debug` entries in the list are debug packages — exclude from the ISO.
7. **DKMS coverage gaps** — `facetimehd` is built **only** for the `-rt-lts` kernel (missing on `-lts`
   and `-rt`). Ensure all DKMS modules build for every shipped kernel (need matching `*-headers`).
8. **Bootloader config** — `/boot` is root-only (couldn't read as user). Capture with sudo:
   `bootctl status`, `/boot/loader/`, kernel cmdline, ESP layout. Kernels derived from packages
   (`linux-lts`/`-rt`/`-rt-lts`); `kernels.txt` is empty because of ESP perms.
9. **Secrets to EXCLUDE/scrub** — `~/.zshenv.secret` (sourced by `.zshenv`), `REGISTRATION_CODE`,
   `~/.config/BraveSoftware/` profile (only the flag files were captured), GPG/SSH keys, `pass` store.
10. **Personal data to scrub** — saved Wi-Fi SSIDs in `xfce4-panel.xml`, weather location ([location]),
    timezones ([tz redacted], [tz redacted]), wallpaper paths, hardcoded `/home/user` and
    `/home/user` paths in panel launchers, scripts, and the alacritty self-referential symlink.
11. **External app installs** — Blender (`~/Applications`), FreeCAD/Ondsel/Friction AppImages,
    Tor Browser (`/opt`), `~/.cargo` (rustup), `~/.npm-global`, `~/.tmux/plugins` (TPM). Decide which
    DevOS ships vs. documents as post-install.
12. **Audio stack ambiguity** — both PulseAudio (autostart + pkgs) and PipeWire (user units) are present.
    Pick one canonical path for DevOS (recommend PipeWire + `pipewire-jack`, keep JACK2 for pro use).
13. **xinitrc resolution is hardcoded** (`eDP-1 1680x1050@60`) — make conditional/auto for other hardware.

---

## 7. Recommended archiso profile structure

Start from `/usr/share/archiso/configs/releng/` (you already have `archiso` installed):

```
devos/
├── profiledef.sh                 # ISO name=devos, label, applications, file perms (mode of custom scripts!)
├── pacman.conf                   # core/extra/multilib + [devos-local] custom repo (for AUR builds)
├── packages.x86_64               # ← seed from packages-repo.txt (549), minus *-debug, plus prebuilt-AUR names
├── bootstrap_packages.x86_64
├── efiboot/  syslinux/  grub/    # bootloader menus (match systemd-boot target if used)
├── airootfs/                     # the live/installed root overlay
│   ├── etc/
│   │   ├── environment            # XDG_DESKTOP_PORTAL, LIBVA_DRIVER_NAME=i965, PYTHONPATH
│   │   ├── mkinitcpio.conf        # the HOOKS line above
│   │   ├── X11/xorg.conf.d/       # 00-keyboard, 10-intel, 40-libinput, 50-magicmouse, 99-disable-vkbd
│   │   ├── systemd/system/        # daw-prep, daw.target, pin-*, disable-*, hugepages, snd-usb-audio, …
│   │   │   └── multi-user.target.wants/  # symlinks = enabled services
│   │   ├── modprobe.d/  sysctl.d/ udev/rules.d/   # (capture realtime/audio tunings with sudo)
│   │   └── skel/                  # → becomes every new user's $HOME
│   │       ├── .zshenv .zshrc .bashrc .profile .xinitrc .p10k.zsh
│   │       └── .config/{alacritty,nvim,picom.conf,libinput-gestures.conf,
│   │                     brave-nightly-flags.conf,
│   │                     xfce4/xfconf/xfce-perchannel-xml/*.xml,
│   │                     systemd/user/*}
│   ├── usr/local/bin/             # dwm, slstatus, daw, daw-prep.sh, clean_caches, greeter scripts, …
│   └── root/customize_airootfs.sh # locale-gen, enable services, build AUR→local repo, useradd reaper, groups
├── local-repo/                   # prebuilt AUR .pkg.tar.zst (brave-nightly-bin, vscode, dwm-systray, …)
└── build steps                   # mkarchiso -v -w work/ -o out/ devos/
```

Conventions:
- **`profiledef.sh` `file_permissions`** must mark `/usr/local/bin/*` and greeter scripts `0:0:755`.
- Enabled services = symlinks under `airootfs/etc/systemd/system/*.target.wants/` (mirror §5 base list).
- DKMS: include every kernel's `*-headers` so modules build in `customize_airootfs.sh` (or on first boot).
- Keep AUR out of `packages.x86_64`; build it into `local-repo/` and reference via a `[devos-local]` repo.

---

## 8. Phase 1 TODO (ordered — to begin the DevOS repo)

1. **Init the repo.** `git init devos`; commit this `~/devos-blueprint/` as `docs/blueprint/` (raw captures + this file).
2. **Scaffold the profile.** `cp -r /usr/share/archiso/configs/releng devos/profile`; rename to DevOS in `profiledef.sh`.
3. **Seed packages.** Copy `packages-repo.txt` → `profile/packages.x86_64`; strip `*-debug`; validate each
   exists in core/extra/multilib (`pacman -Si`); move anything that doesn't to the AUR build list.
4. **Capture the root-only bits (needs sudo on `workstation`).** Bootloader (`bootctl status`, `/boot/loader/`,
   kernel cmdline), `/etc/modprobe.d`, `/etc/sysctl.d`, `/etc/udev/rules.d`, `/etc/security/limits.d`
   (realtime limits), `daw.target`, and the full greeter chain. Add to `airootfs/etc/`.
5. **Build skel.** Place scrubbed dotfiles + `xfce-perchannel-xml/*.xml` + user systemd units into
   `airootfs/etc/skel/`. Rewrite all `/home/user` and `/home/user` paths to `$HOME`/generic.
6. **Vendor custom binaries/scripts.** Add `~/dwm-config/dwm-6.5` source (+ slstatus) to the repo; build
   in `customize_airootfs.sh`. Copy the curated `/usr/local/bin` toolkit.
7. **Stand up the AUR pipeline.** Script `paru`/`makepkg` builds of the 162 foreign pkgs into `local-repo/`;
   wire `[devos-local]` into the profile `pacman.conf`.
8. **Write `customize_airootfs.sh`.** locale-gen, set vconsole font, create `wheel`/`audio` users + groups
   (`realtime`, `audio`, `docker`, …), enable the §5 service set, install DKMS modules, apply skel.
9. **Decide the canonical audio + login model** (PipeWire vs Pulse; custom greeter vs `ly`) and the DAW-mode
   UX (`daw.target` toggle). Document as DevOS's two headline features.
10. **First build + boot test.** `mkarchiso -v -w work -o out devos/profile`; boot in QEMU; verify dwm + XFCE
    sessions, gestures, audio, and `daw.target` switching. Iterate.

---

### Appendix — raw capture files in `~/devos-blueprint/`
`pacman-explicit.txt`, `aur-packages.txt`, `packages-repo.txt`, `dkms-modules.txt`, `kernels.txt` (empty—see §6),
`dev-versions.txt`, `config-inventory.txt`, `system-identity.txt`, `services-autostart-env.txt`,
`xfconf-*.txt` (dumps), `xfce-xml/*.xml` (canonical), `dotfiles/*`, `system/{systemd,systemd-user,xorg.conf.d,local-bin}/*`.
