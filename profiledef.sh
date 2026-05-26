#!/usr/bin/env bash
# DevOS archiso profile definition.
# Build:  mkarchiso -v -w /tmp/devos-work -o ./out .
# shellcheck disable=SC2034

iso_name="devos"
iso_label="DEVOS_$(date +%Y%m)"
iso_publisher="DevOS"
iso_application="DevOS Live / Installer (Arch-based, XFCE)"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr'
           'bios.syslinux.eltorito'
           'uefi-x64.systemd-boot.esp'
           'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto' '--long')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/usr/local/bin"]="0:0:755"
  ["/etc/skel"]="0:0:755"
)
