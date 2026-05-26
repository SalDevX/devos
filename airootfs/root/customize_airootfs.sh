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
useradd -m -s /usr/bin/zsh user 2>/dev/null || true
for g in wheel audio video input render; do   # docker + realtime dropped (see README / MusicOS)
  groupadd -f "$g"
  gpasswd -a user "$g" >/dev/null 2>&1 || true
done
echo 'user:user' | chpasswd      # live-ISO demo credential only
chage -d 0 user                  # force password change at first login
passwd -l root                   # lock root — no direct root login

# ----------------------------------------------------------------------
# sudo: password-required for wheel, via a validated drop-in (not sed on sudoers).
# ----------------------------------------------------------------------
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel
visudo -cf /etc/sudoers.d/wheel >/dev/null   # syntax-check; aborts build if invalid

# ----------------------------------------------------------------------
# Autologin user on tty1 -> ~/.zprofile shows the MOTD once, then runs startx.
# Remove this drop-in to require a normal TTY login.
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
           ufw fail2ban cups cronie acpid bluetooth tlp; do
  systemctl enable "$svc" >/dev/null 2>&1 || true
done

# Touchpad / Magic-Trackpad gestures for every user (survives reboots).
systemctl --global enable libinput-gestures.service >/dev/null 2>&1 || true

# Hardware-specific services (mbpfan, thermald, disable-apple-*, disable-wakeup)
# are enabled at FIRST BOOT on the real target, not here.
systemctl enable devos-firstboot.service >/dev/null 2>&1 || true

# ----------------------------------------------------------------------
# Live ISO: Install DevOS desktop shortcut for the live user only.
# Goes directly into /home/user — NOT into /etc/skel — so the installed
# system never inherits it. The cleanup.sh Calamares step removes it
# from /mnt if it somehow ends up there.
# ----------------------------------------------------------------------
mkdir -p /home/user/Desktop
cat > /home/user/Desktop/install-devos.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install DevOS
Comment=Install DevOS to your disk
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
EOF
chmod +x /home/user/Desktop/install-devos.desktop
chown -R user:user /home/user/Desktop

# ----------------------------------------------------------------------
# Regenerate initramfs if a kernel is present in the image.
# ----------------------------------------------------------------------
command -v mkinitcpio >/dev/null && mkinitcpio -P || true
