#!/usr/bin/env bash
# Runs inside the airootfs chroot during `mkarchiso`. Configures the DevOS image.
#
# IMPORTANT: this executes on the BUILD host (often CI), NOT the end-user machine.
# Hardware-specific service enabling is therefore deferred to first boot on the real
# target via devos-firstboot.service (/usr/local/bin/devos-firstboot).
set -eu

# ----------------------------------------------------------------------
# Hardware detection. At build time this reflects the BUILD host (useful only
# as a log line); the authoritative per-machine gate runs at first boot.
# ----------------------------------------------------------------------
detect_hardware() {
  if dmidecode -s system-manufacturer 2>/dev/null | grep -qi apple; then
    IS_APPLE=yes; else IS_APPLE=no; fi
  if grep -qi GenuineIntel /proc/cpuinfo 2>/dev/null; then
    IS_INTEL=yes; else IS_INTEL=no; fi
}
detect_hardware
echo "customize_airootfs: build host Apple=$IS_APPLE Intel=$IS_INTEL (real gate = first boot)" >&2

# ----------------------------------------------------------------------
# Locale & timezone (defaults; users override after install):
#   change locale:   localectl set-locale LANG=de_DE.UTF-8
#   change timezone: timedatectl set-timezone Europe/Berlin
# ----------------------------------------------------------------------
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# ----------------------------------------------------------------------
# Default user — login shell zsh. Password is 'user' for the LIVE-ISO autologin
# demo, but it is EXPIRED (chage -d 0) so an installed system forces a change at
# first login. Root login is LOCKED (use sudo).
# ----------------------------------------------------------------------
chown -R root:root /etc/skel
# mkarchiso copies airootfs with cp --no-preserve=mode (mkarchiso:316), so every
# exec bit under /etc/skel is LOST at build. Restore them BEFORE useradd -m
# clones skel into /home/user: keybindings spawn machud by name (a 0644 copy
# gives "Permission denied"), and .xinitrc//etc/xprofile gate display.sh/
# panel-dynamic.sh behind [ -x ] so they silently never run without this.
chmod 0755 /etc/skel/.local/bin/* \
           /etc/skel/.config/devos/*.sh \
           /etc/skel/.config/xfce4/xfdashboard-startup.sh
find /etc/skel/.tmux -type f \( -name '*.sh' -o -name '*.tmux' -o -name '*.exp' \) \
     -exec chmod 0755 {} + 2>/dev/null || true
find /etc/skel/.config/rofi -type f -name '*.sh' -exec chmod 0755 {} + 2>/dev/null || true
useradd -m -s /usr/bin/zsh user 2>/dev/null || true
for g in wheel audio video input render; do   # docker + realtime dropped (see README / MusicOS)
  groupadd -f "$g"
  gpasswd -a user "$g" >/dev/null 2>&1 || true
done
echo 'user:user' | chpasswd      # live-ISO demo credential only
passwd -l root                   # lock root — no direct root login

# ----------------------------------------------------------------------
# sudo: password-required for wheel, via a validated drop-in (not sed on sudoers).
# ----------------------------------------------------------------------
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel
visudo -cf /etc/sudoers.d/wheel >/dev/null   # syntax-check; aborts build if invalid

# ----------------------------------------------------------------------
# Autologin user on tty1 -> ~/.zprofile shows the MOTD once, then runs startx.
# The live ISO has NO display manager: SDDM is shipped in the squashfs but is
# enabled ONLY on the installed target by the Calamares installer (devossetup /
# install.sh), never on the live boot. Remove this drop-in for a normal login.
# ----------------------------------------------------------------------
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin user --noclear %I $TERM
EOF

# ----------------------------------------------------------------------
# Always-on, hardware-agnostic services.
# NOTE: sshd is intentionally NOT enabled by default — it would expose SSH with
# the demo password. Enable it yourself after setting a real password.
# ----------------------------------------------------------------------
for svc in NetworkManager systemd-resolved systemd-timesyncd \
           ufw fail2ban cups cronie acpid bluetooth tlp reflector; do
  systemctl enable "$svc" >/dev/null 2>&1 || true
done

# Broadcom Mac Wi-Fi firmware stager — lands the (non-redistributable) BCM4364/4377
# firmware from a baked airootfs slot or a FAT USB/EFI BEFORE the driver loads, so
# Wi-Fi works in the live "try it" session. No-op when firmware is already present.
systemctl enable devos-wifi-firmware.service >/dev/null 2>&1 || true

# Broadcom Wi-Fi driver auto-select — runs before NetworkManager on the live ISO
# and the installed system so wl (BCM4360) and brcmfmac (BCM4364 / BCM4377) never
# fight for the card. Hardware-agnostic: the helper no-ops on non-Broadcom machines.
systemctl enable devos-wifi-driver.service >/dev/null 2>&1 || true

# Touchpad / Magic-Trackpad gestures for every user (survives reboots).
systemctl --global enable libinput-gestures.service >/dev/null 2>&1 || true

# Hardware-specific services (mbpfan, thermald, disable-apple-*, disable-wakeup)
# are enabled at FIRST BOOT on the real target, not here.
systemctl enable devos-firstboot.service >/dev/null 2>&1 || true

# NOTE: SDDM (the macOS greeter) is intentionally NOT enabled on the live ISO.
# The live boot stays agetty->startx->XFCE (which auto-launches Calamares). The
# Calamares installer (devossetup / install.sh) enables sddm, sets
# graphical.target, and points the greeter at the Qt6 binary on the INSTALLED
# system only — so the live ISO never shows the greeter and never autologins via
# a display manager.

# ----------------------------------------------------------------------
# Live ISO: sudoers rule so the live user can launch Calamares without a
# password prompt. devos-calamares wrapper (in airootfs) calls sudo -E so
# the X display environment is preserved. SETENV is required for sudo -E.
# The devoscleanup Calamares module removes this from the installed target.
# ----------------------------------------------------------------------
# /etc/sudoers.d/zz-live-user is placed directly by the archiso profile (profiledef.sh
# sets mode 440). Named zz-* so it sorts AFTER sudoers.d/wheel alphabetically,
# ensuring NOPASSWD: ALL wins over the wheel password requirement for the live user.

# Make devos-calamares wrapper executable (archiso does not auto-chmod binaries).
chmod 0755 /usr/local/bin/devos-calamares

# ----------------------------------------------------------------------
# SDDM login wallpaper (per-machine, mutable). The greeter runs as the
# unprivileged `sddm` user and can't read /home, so it reads its background from
# /var/lib/devos/sddm-wallpaper.jpg. Make that dir wheel-writable (setgid) +
# world-readable so the XFCE session helper (devos-sddm-wallpaper-sync) can
# mirror the user's chosen wallpaper into it with NO root/polkit, while sddm can
# still read it. Ships defaulted to the greeter's bundled image; devossetup /
# install.sh re-assert these perms on the installed target.
# ----------------------------------------------------------------------
install -d -m 2775 /var/lib/devos
chgrp wheel /var/lib/devos
chmod 2775 /var/lib/devos
if [ -f /var/lib/devos/sddm-wallpaper.jpg ]; then
  chgrp wheel /var/lib/devos/sddm-wallpaper.jpg
  chmod 0664 /var/lib/devos/sddm-wallpaper.jpg
fi
# Per-user login avatars: devos-sddm-avatar-sync publishes ~/.face here as
# <user>.face.icon and SDDM's FacesDir points at it. Same wheel-writable
# (setgid) + world-readable scheme as the wallpaper dir above.
install -d -m 2775 /var/lib/devos/faces
chgrp wheel /var/lib/devos/faces
chmod 2775 /var/lib/devos/faces
chmod 0755 /usr/local/bin/devos-sddm-wallpaper-sync
chmod 0755 /usr/local/bin/devos-sddm-avatar-sync

# ----------------------------------------------------------------------
# Live ISO: Install DevOS desktop shortcut for the live user only.
# Goes directly into /home/user — NOT into /etc/skel — so the installed
# system never inherits it. Uses devos-calamares (sudo -E) instead of bare
# pkexec, which has no polkit action defined for Calamares.
# The devoscleanup Calamares module removes this from the target if it ends up there.
# ----------------------------------------------------------------------
mkdir -p /home/user/Desktop
cat > /home/user/Desktop/install-devos.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install DevOS
Comment=Install DevOS to your disk
Exec=devos-calamares
Icon=calamares
Terminal=false
Categories=System;
EOF
chmod +x /home/user/Desktop/install-devos.desktop
# metadata::trusted is set at first XFCE login via /etc/xdg/autostart/devos-trust-launcher.desktop
# (gio set requires GVfs daemon which is not present in the build chroot).
chown -R user:user /home/user/Desktop

# ----------------------------------------------------------------------
# Rebuild fontconfig cache so Geist (and any other bundled fonts) are
# visible to Plymouth's Image.Text() calls during early boot.
# ----------------------------------------------------------------------
fc-cache -f /usr/share/fonts/geist /usr/share/fonts/menlo /usr/share/plymouth/themes/devos || true

# ----------------------------------------------------------------------
# Set Plymouth default theme before rebuilding initramfs.
# Creates the default.plymouth symlink that the Plymouth mkinitcpio hook
# reads to decide which theme to embed. Must run AFTER fc-cache (above)
# so fc-match "Geist Light 48" resolves correctly. Do NOT add || true —
# if this fails, the wrong theme or no font gets embedded and the splash
# renders as a black screen (Sprite(null) is a silent no-op in Ply).
plymouth-set-default-theme devos

# Rebuild initramfs. Must run AFTER plymouth-set-default-theme and fc-cache.
# Do NOT add || true — a silent failure here causes the ISO to ship the
# package-install-time initramfs (built before fc-cache), which embeds
# the wrong font and makes the Plymouth splash appear pitch-black.
# ----------------------------------------------------------------------
mkinitcpio -P
