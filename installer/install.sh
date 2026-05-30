#!/usr/bin/env bash
# DevOS guided installer — CLI fallback for the Calamares GUI installer.
#
# Produces an installed system identical to the Calamares path by mirroring its
# three native Python job modules plus the built-in modules pacstrap used to
# cover for free:
#   copyairootfs  -> rsync the running live system onto the target
#   machineid     -> regenerate /etc/machine-id (never ship the live ISO's id)
#   fstab         -> fresh genfstab
#   devossetup    -> skel, firstboot, services, sudoers, HOOKS, locale
#   initcpio      -> rebuild initramfs against the installed HOOKS
#   bootloader    -> systemd-boot + PARTUUID entries
#   devoscleanup  -> strip live-only artefacts
#
# KEEP IN SYNC: devos/airootfs/etc/calamares/modules/{copyairootfs,devossetup,
# devoscleanup}/main.py are the canonical copies of this logic. If you change a
# service, a HOOK, an rsync exclude, or a cleanup path there, change it here too.
#
# This is NOT auto-destructive: it does not partition or format anything.
# Prereqs (do these yourself first):
#   - partition the disk (GPT: an EFI System Partition + a root partition)
#   - mkfs the partitions
#   - mount root at /mnt and the ESP at /mnt/boot
# Then:  sudo ./installer/install.sh
set -euo pipefail
PROFILE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=/mnt

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
mountpoint -q "$ROOT"      || { echo "Mount your target root at /mnt first."; exit 1; }
mountpoint -q "$ROOT/boot" || { echo "Mount your EFI System Partition at /mnt/boot first."; exit 1; }

read -rp "This will install DevOS onto /mnt by copying the live system. Continue? [y/N] " ok
[[ ${ok,,} == y ]] || exit 1

# --- copyairootfs: rsync the live system to the target ----------------------
# No internet, no pacstrap — every bundled package is already on the live fs.
echo ">> copying live system to $ROOT (rsync — no internet needed)"
rsync -aAXH --info=progress2 \
    --exclude=/proc/ --exclude=/sys/ --exclude=/run/ --exclude=/tmp/ \
    --exclude=/mnt/ --exclude=/lost+found --exclude=/home/ \
    / "$ROOT/"
install -d -m 0755 "$ROOT/proc" "$ROOT/sys" "$ROOT/run"
install -d -m 1777 "$ROOT/tmp"
install -d -m 0755 "$ROOT/home"

# Install the kernel + microcode into /boot — the live archiso /boot is empty
# (archiso boots the kernel from the ISO), so the rsync copied none. Prefer the
# image in the modules tree (version-matched); fall back to the ISO boot mount.
# Mirror of copyairootfs._ensure_boot_kernel.
echo ">> installing kernel + microcode into /boot"
KIMG="$(ls "$ROOT"/usr/lib/modules/*/vmlinuz 2>/dev/null | head -1)"
[[ -n "$KIMG" ]] || KIMG="$(ls /run/archiso/bootmnt/*/boot/*/vmlinuz-linux-lts 2>/dev/null | head -1)"
[[ -n "$KIMG" ]] || { echo "ERROR: linux-lts kernel image not found"; exit 1; }
install -Dm644 "$KIMG" "$ROOT/boot/vmlinuz-linux-lts"
UCODE="$(ls /run/archiso/bootmnt/*/boot/intel-ucode.img 2>/dev/null | head -1)"
[[ -n "$UCODE" ]] && install -Dm644 "$UCODE" "$ROOT/boot/intel-ucode.img"

# --- machineid: the rsync copied the live id; regenerate a unique one --------
echo ">> regenerating machine-id"
rm -f "$ROOT/etc/machine-id"
arch-chroot "$ROOT" systemd-machine-id-setup

# --- fstab: overwrite (not append) so the live fstab never leaks through -----
echo ">> genfstab"
genfstab -U "$ROOT" > "$ROOT/etc/fstab"

# --- devossetup: skel, firstboot, services, sudoers, HOOKS, locale ----------
echo ">> configuring installed system"
cp -aT /etc/skel "$ROOT/etc/skel"
install -Dm644 /etc/systemd/system/devos-firstboot.service \
    "$ROOT/etc/systemd/system/devos-firstboot.service"
install -Dm755 /usr/local/bin/devos-firstboot \
    "$ROOT/usr/local/bin/devos-firstboot"

# Service list — mirror of devossetup.SERVICES.
for svc in NetworkManager systemd-resolved systemd-timesyncd \
           ufw fail2ban cups cronie acpid bluetooth tlp; do
    arch-chroot "$ROOT" systemctl enable "$svc" 2>/dev/null || true
done
arch-chroot "$ROOT" systemctl --global enable libinput-gestures.service 2>/dev/null || true
arch-chroot "$ROOT" systemctl enable devos-firstboot.service 2>/dev/null || true

echo '%wheel ALL=(ALL:ALL) ALL' > "$ROOT/etc/sudoers.d/wheel"
chmod 0440 "$ROOT/etc/sudoers.d/wheel"

# mkinitcpio HOOKS — mirror of devossetup.INSTALLED_HOOKS (drop the archiso
# hooks, keep Plymouth for the installed system).
rm -f "$ROOT/etc/mkinitcpio.conf.d/archiso.conf"
cat > "$ROOT/etc/mkinitcpio.conf.d/devos.conf" << 'MKINITCPIO'
HOOKS=(base udev autodetect microcode modconf kms plymouth keyboard keymap consolefont block filesystems fsck)
MKINITCPIO

sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' "$ROOT/etc/locale.gen"
arch-chroot "$ROOT" locale-gen
arch-chroot "$ROOT" dconf update 2>/dev/null || true

# --- initcpio: rebuild against the installed HOOKS (live initramfs is archiso) -
echo ">> rebuilding initramfs"
arch-chroot "$ROOT" mkinitcpio -P

# --- bootloader: systemd-boot + entries (PARTUUID auto-detected from /mnt) ---
echo ">> systemd-boot + entries"
arch-chroot "$ROOT" bootctl install
ROOT_PARTUUID="$(findmnt -no PARTUUID "$ROOT")"
install -d "$ROOT/boot/loader/entries"
cp "$PROFILE_DIR/installer/loader/loader.conf" "$ROOT/boot/loader/loader.conf"
for e in devos devos-fallback; do
  sed "s/YOUR-PARTUUID-HERE/${ROOT_PARTUUID}/" \
    "$PROFILE_DIR/installer/loader/entries/${e}.conf" > "$ROOT/boot/loader/entries/${e}.conf"
done

# --- devoscleanup: strip live-only artefacts --------------------------------
echo ">> removing live-only artefacts"
rm -f "$ROOT/etc/skel/Desktop/install-devos.desktop"
find "$ROOT/home" -name "install-devos.desktop" -delete 2>/dev/null || true
rm -rf "$ROOT/etc/calamares"
rm -f "$ROOT/etc/xdg/autostart/calamares.desktop"
rm -f "$ROOT/etc/xdg/autostart/devos-trust-launcher.desktop"
rm -f "$ROOT/etc/sudoers.d/zz-live-user"
rm -f "$ROOT/usr/local/bin/devos-calamares"
# Live autologin drop-in (agetty --autologin user): installed system uses a
# normal login prompt. (devoscleanup does the same for the GUI path.)
rm -f "$ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf"
rmdir "$ROOT/etc/systemd/system/getty@tty1.service.d" 2>/dev/null || true

# The CLI path keeps the live 'user' account, but its home was excluded from the
# copy — recreate it from skel so login + startx work.
if arch-chroot "$ROOT" id -u user >/dev/null 2>&1; then
  install -d -m 0700 "$ROOT/home/user"
  cp -aT "$ROOT/etc/skel" "$ROOT/home/user"
  arch-chroot "$ROOT" chown -R user:user /home/user
fi

echo ">> Done. Set the user/root passwords in the target if needed:"
echo "     arch-chroot /mnt passwd user"
echo "   then:  umount -R /mnt && reboot"
