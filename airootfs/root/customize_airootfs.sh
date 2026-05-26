#!/usr/bin/env bash
# Runs inside the airootfs chroot during `mkarchiso`. Sets up the live DevOS.
set -e

# --- locale / time ---
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# --- default user (login shell zsh; password 'user' — change after install) ---
useradd -m -s /usr/bin/zsh user 2>/dev/null || true
for g in wheel audio video input render realtime docker; do
  groupadd -f "$g"
  gpasswd -a user "$g" >/dev/null 2>&1 || true
done
echo 'user:user' | chpasswd
echo 'root:root' | chpasswd
# sudo for wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- autologin user on tty1 -> .zprofile runs startx -> XFCE ---
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin user --noclear %I $TERM
EOF

# --- services (guarded: laptop/Apple units may be absent on other hardware) ---
for svc in NetworkManager systemd-resolved systemd-timesyncd sshd ufw fail2ban \
           cups cronie acpid bluetooth thermald tlp mbpfan \
           disable-apple-display-audio.service disable-usb-autosuspend.service \
           disable-wakeup.service; do
  systemctl enable "$svc" >/dev/null 2>&1 || true
done

# --- regenerate initramfs for the installed-system kernel if present ---
command -v mkinitcpio >/dev/null && mkinitcpio -P || true
