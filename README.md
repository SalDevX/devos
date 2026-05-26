# DevOS

An Arch-based Linux distribution built with `archiso`, cloned from a golden
developer workstation. **DevOS = XFCE desktop on the LTS kernel**, dev toolchains,
Apple/MacBook hardware enablement, and hardened defaults.

> The realtime-audio / DAW layer (dwm session, `linux-rt` kernels, JACK/LV2 stack,
> `daw.target` isolation) is intentionally **not** here — that's the separate
> **MusicOS** project.

## Repo layout

```
devos/
├── profiledef.sh            # archiso ISO metadata + file permissions
├── pacman.conf              # build-time repos (+ optional [devos-local] for AUR)
├── packages.x86_64          # 467 repo packages (RT kernels + 78 DAW pkgs → MusicOS)
├── aur-build-list.txt       # 126 AUR build targets (priority-ordered)
├── airootfs/                # overlay applied to the live/installed root
│   ├── etc/
│   │   ├── os-release hostname locale.conf vconsole.conf environment
│   │   ├── modprobe.d/ sysctl.d/ udev/rules.d/ modules-load.d/
│   │   ├── X11/xorg.conf.d/  # keyboard, intel TearFree, libinput, magic-mouse
│   │   ├── acpi/             # CLAMSHELL: events/ + actions/lid.handler.sh + handler.sh
│   │   ├── systemd/system/   # disable-apple-display-audio, disable-usb-autosuspend, disable-wakeup
│   │   ├── systemd/logind.conf.d/  # 10-devos-lid.conf — HandleLidSwitch=ignore (acpid owns lid)
│   │   └── skel/             # the scrubbed, publishable dotfiles (see below)
│   └── root/customize_airootfs.sh   # build-time setup (user, services, autologin)
├── installer/
│   ├── etc/mkinitcpio.conf
│   ├── loader/{loader.conf,entries/devos.conf,entries/devos-fallback.conf}
│   └── install.sh           # guided disk install (systemd-boot, PARTUUID auto-detected)
├── tools/scrub.sh           # personal-data scrubber (idempotent)
├── tools/build-aur-repo.sh  # makepkg loop → local pacman repo (devos-local)
└── docs/
```

## Build the ISO

```bash
sudo pacman -S archiso
cd devos
sudo mkarchiso -v -w /tmp/devos-work -o ./out .
```

### AUR packages (one-time, before building)
`packages.x86_64` is **repo-only**. The **126** AUR/foreign packages for DevOS are in
`aur-build-list.txt` (priority-ordered: `brave-bin`, `xfdashboard`, `libinput-gestures`,
`ttf-ms-fonts`, shell/term tools, …). Build them into a local repo with the included
script, then uncomment `[devos-local]` in `pacman.conf`:

```bash
./tools/build-aur-repo.sh ~/devos-local        # makepkg loop over aur-build-list.txt
cat ~/devos-local/devos-aur-built.txt >> packages.x86_64
```

> Browser: ship **Brave stable** (`brave-bin`), not nightly. Its tuned flags are in
> `airootfs/etc/skel/.config/brave-flags.conf` (Haswell GPU workarounds); on stable the
> config dir is `~/.config/BraveSoftware/Brave-Browser` (not `…-Beta`).

### Package caveats
- RT kernels removed (MusicOS). DevOS ships `linux-lts`.
- The 78 DAW/LV2 packages were **split out to a separate MusicOS repo** (repo + AUR lists);
  `packages.x86_64` is now 467 dev-focused packages.
- Validate every name resolves: any unavailable package will stop `pacstrap`/`mkarchiso`.

## Install to disk

### 1 — Connect to WiFi (skip if using ethernet)

The `wl` module (Broadcom BCM) loads automatically on boot. Connect before running
the installer — `pacstrap` needs internet:

```bash
nmtui        # TUI: pick your network, enter password, Activate
# or
nmcli device wifi connect "SSID" password "passphrase"
```

Verify: `ping -c1 archlinux.org`

### 2 — Partition the disk

```bash
lsblk                        # identify target (e.g. /dev/sda, /dev/nvme0n1)
cfdisk /dev/sdX              # GPT → new partition table
                             #   /dev/sdX1  512M   EFI System
                             #   /dev/sdX2  rest   Linux filesystem
                             # Write → Quit
```

### 3 — Format

```bash
mkfs.fat -F32 /dev/sdX1
mkfs.ext4     /dev/sdX2
```

### 4 — Mount

```bash
mount          /dev/sdX2 /mnt
mount --mkdir  /dev/sdX1 /mnt/boot
```

### 5 — Run the installer

```bash
sudo ./installer/install.sh
```

It runs `pacstrap`, `genfstab`, copies the `airootfs/etc` overlay + skel, installs
**systemd-boot**, and writes loader entries with the **root PARTUUID auto-detected**
from `/mnt` (replacing the `YOUR-PARTUUID-HERE` placeholder). Default credentials are
`user/user` and `root/root` — change them immediately.

## Login model
No display manager, no greeter. `getty` autologins `user` on **tty1**, whose
`.zprofile` runs `startx` → `.xinitrc` → **XFCE**. Disable autologin by removing
`/etc/systemd/system/getty@tty1.service.d/autologin.conf`.

## Clamshell / display switching (custom acpid logic)
`logind`'s `HandleLidSwitch` is disabled (`logind.conf.d/10-devos-lid.conf`); acpid
owns the lid via `airootfs/etc/acpi/actions/lid.handler.sh`: lid-closed + external →
internal panel `--off` + external primary; lid-closed + no external → `suspend`;
lid-open → restore dual/internal + relaunch xfdashboard. Output names `eDP1`/`DP2`
are **hardware-specific** — see docs/BLUEPRINT.md §5.5.

## Privacy / scrub
`tools/scrub.sh` already ran on `airootfs/etc/skel`. It removed:
- the source user's `/home/<user>` paths and bare username → `/home/user` / `user`
- XFCE panel systray memory incl. **saved Wi-Fi SSIDs**, recent-apps, favorites
- weather location (coords/name/timezone) and panel background-image path
- author name from a config comment

**Excluded entirely** (never captured/committed): `~/.zshenv.secret`, the Brave
profile, GPG/SSH keys. Re-run after dropping fresh configs in:
`tools/scrub.sh airootfs/etc/skel <old-user>`.

## Hardware notes (source was an Apple MacBook, Intel Haswell)
Kept because they're harmless elsewhere and guarded, but **remove for generic x86**:
`modprobe.d` (i915 PSR/FBC, magicmouse, usb-autosuspend), `udev/rules.d`
(apple-display-audio, magic-mouse, apple-superdrive), `xorg.conf.d/50-magicmouse.conf`,
the two `disable-apple-*` services, and `intel-ucode`/`i965` assumptions. Dev/embedded
udev rules (J-Link, PlatformIO, Microchip) are kept on purpose.

## Still manual (see docs/BLUEPRINT.md §6)
- Build/validate the AUR local repo (`tools/build-aur-repo.sh`).
- Confirm the systemd-boot kernel cmdline on the target (`sudo bootctl status`); the
  placeholder root PARTUUID is auto-filled by `install.sh`.
- `nvim` config is a separate git repo — clone it into the skel or document it.

## Docker (opt-in)
Docker is **not** enabled by default and the `docker` group is **not** pre-created —
running the daemon and granting socket access is a privilege decision each user makes.
To opt in:

```bash
sudo pacman -S --needed docker        # already present if kept in packages.x86_64
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"       # log out/in for the group to apply
```

## License
- **Repo scripts & configs** (`profiledef.sh`, `tools/`, `installer/`, `airootfs/` overlays,
  and the dotfiles in `airootfs/etc/skel`) — **MIT**, see `LICENSE`.
- **Bundled software** pulled via `packages.x86_64` / `aur-build-list.txt` is **not** covered
  by that grant; each package keeps its upstream license. The base system and much of the
  toolchain are **GPL-3.0** (plus other OSI licenses). DevOS only assembles and configures them.
