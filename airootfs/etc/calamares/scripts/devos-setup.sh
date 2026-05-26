#!/usr/bin/env bash
set -euo pipefail

ROOT=/mnt

echo "[devos] copying /etc overlay"
cp -aT /etc/calamares/airootfs-etc /mnt/etc

echo "[devos] enabling services"
for svc in NetworkManager systemd-resolved systemd-timesyncd \
           ufw fail2ban cups cronie acpid bluetooth tlp; do
    arch-chroot "$ROOT" systemctl enable "$svc" 2>/dev/null || true
done
arch-chroot "$ROOT" systemctl --global enable libinput-gestures.service 2>/dev/null || true
arch-chroot "$ROOT" systemctl enable devos-firstboot.service 2>/dev/null || true

echo "[devos] sudoers"
echo '%wheel ALL=(ALL:ALL) ALL' > "$ROOT/etc/sudoers.d/wheel"
chmod 0440 "$ROOT/etc/sudoers.d/wheel"

echo "[devos] locale & timezone"
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$ROOT/etc/locale.gen"
arch-chroot "$ROOT" locale-gen

echo "[devos] setup complete"
