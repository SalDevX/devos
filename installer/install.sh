#!/usr/bin/env bash
# DevOS guided installer — run from the live ISO (or any Arch live env).
# This is NOT auto-destructive: it does not partition or format anything.
#
# Prereqs (do these yourself first):
#   - partition the disk (GPT: an EFI System Partition + a root partition)
#   - mkfs the partitions
#   - mount root at /mnt and the ESP at /mnt/boot
#
# Then:  sudo ./installer/install.sh
set -euo pipefail
PROFILE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
mountpoint -q /mnt        || { echo "Mount your target root at /mnt first."; exit 1; }
mountpoint -q /mnt/boot   || { echo "Mount your EFI System Partition at /mnt/boot first."; exit 1; }

read -rp "This will pacstrap DevOS onto /mnt. Continue? [y/N] " ok
[[ ${ok,,} == y ]] || exit 1

echo ">> pacstrap base + kernel + DevOS packages"
mapfile -t PKGS < <(grep -vE '^\s*#|^\s*$' "$PROFILE_DIR/packages.x86_64")
# Repo packages only. AUR names (see ../aur-packages.txt) must come from a local
# repo; if any package is missing, pacstrap will stop — drop it or build it first.
pacstrap -K /mnt base linux-lts linux-lts-headers linux-firmware intel-ucode "${PKGS[@]}"

echo ">> genfstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">> overlay /etc configs + skel + installer mkinitcpio.conf"
cp -aT "$PROFILE_DIR/airootfs/etc" /mnt/etc
[[ -f "$PROFILE_DIR/installer/etc/mkinitcpio.conf" ]] && \
  cp "$PROFILE_DIR/installer/etc/mkinitcpio.conf" /mnt/etc/mkinitcpio.conf

echo ">> systemd-boot + entries (PARTUUID auto-detected from /mnt)"
arch-chroot /mnt bootctl install
ROOT_PARTUUID="$(findmnt -no PARTUUID /mnt)"
install -d /mnt/boot/loader/entries
cp "$PROFILE_DIR/installer/loader/loader.conf" /mnt/boot/loader/loader.conf
for e in devos devos-fallback; do
  sed "s/YOUR-PARTUUID-HERE/${ROOT_PARTUUID}/" \
    "$PROFILE_DIR/installer/loader/entries/${e}.conf" > "/mnt/boot/loader/entries/${e}.conf"
done

echo ">> finalize in chroot (locale, user, services, initramfs)"
cp "$PROFILE_DIR/airootfs/root/customize_airootfs.sh" /mnt/root/devos-setup.sh
arch-chroot /mnt bash /root/devos-setup.sh
rm -f /mnt/root/devos-setup.sh

echo ">> Done. Change the default passwords (user/root), then: umount -R /mnt && reboot"
