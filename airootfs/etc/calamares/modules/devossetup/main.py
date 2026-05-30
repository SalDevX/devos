# SPDX-License-Identifier: GPL-3.0-or-later
"""
DevOS Calamares job module: devossetup

Post-copy configuration of the freshly rsynced target system:
  - install skel dotfiles and the devos-firstboot service + helper
  - enable system services in the target (via target_env_call, not arch-chroot)
  - write the wheel sudoers rule
  - swap the live archiso mkinitcpio hooks for the installed-system HOOKS
  - generate the en_US.UTF-8 locale and compile the dconf system db

Native replacement for shellprocess@devos-setup + devos-setup.sh. Reads
rootMountPoint from globalStorage (set by the mount module) and reports hard
failures through Calamares instead of letting shellprocess YAML swallow them.

KEEP IN SYNC: devos/installer/install.sh mirrors this logic for the CLI path.
The SERVICES list and INSTALLED_HOOKS string below are the canonical copy.
"""
import os
import re
import shutil
import subprocess

import libcalamares

# System services enabled in the installed target. Canonical list — mirrored by
# install.sh. Enable failures are non-fatal (a unit may legitimately be absent).
SERVICES = (
    "NetworkManager",
    "systemd-resolved",
    "systemd-timesyncd",
    "ufw",
    "fail2ban",
    "cups",
    "cronie",
    "acpid",
    "bluetooth",
    "tlp",
)

# mkinitcpio HOOKS for the installed system: no archiso/memdisk/pxe hooks;
# autodetect replaces the live vmwgfx/vboxvideo MODULES. Canonical — mirrored
# by install.sh.
INSTALLED_HOOKS = (
    "HOOKS=(base udev autodetect microcode modconf kms plymouth keyboard "
    "keymap consolefont block filesystems fsck)\n"
)

WHEEL_SUDOERS = "%wheel ALL=(ALL:ALL) ALL\n"


def _install(dst, src, mode):
    """Copy src -> dst creating parent dirs, then set mode (like install -D)."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, mode)


def _write(path, text, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, mode)


def _rm(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def _enable(args):
    """systemctl <args> in the target; non-fatal (mirrors the old '|| true')."""
    rc = libcalamares.utils.target_env_call(["systemctl"] + args)
    if rc != 0:
        libcalamares.utils.warning(
            "devossetup: systemctl " + " ".join(args) + " returned " + str(rc))


def _uncomment_locale(path):
    """Uncomment en_US.UTF-8 in locale.gen (mirrors the old sed)."""
    try:
        with open(path) as f:
            content = f.read()
    except FileNotFoundError:
        libcalamares.utils.warning("devossetup: " + path + " not found")
        return
    new = re.sub(r"(?m)^#(en_US\.UTF-8 UTF-8)", r"\1", content)
    if new != content:
        with open(path, "w") as f:
            f.write(new)


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("devossetup failed",
                "rootMountPoint is not set in globalStorage — the mount module "
                "must run before devossetup.")
    libcalamares.utils.debug("devossetup: rootMountPoint=" + root)

    try:
        # 1. skel dotfiles — cp -a fidelity (perms, symlinks, timestamps).
        subprocess.run(["cp", "-aT", "/etc/skel", os.path.join(root, "etc/skel")],
                       check=True)
        # 2. devos-firstboot service + helper.
        _install(os.path.join(root, "etc/systemd/system/devos-firstboot.service"),
                 "/etc/systemd/system/devos-firstboot.service", 0o644)
        _install(os.path.join(root, "usr/local/bin/devos-firstboot"),
                 "/usr/local/bin/devos-firstboot", 0o755)
    except (subprocess.CalledProcessError, OSError) as e:
        return ("devossetup failed", "copying base files failed: " + str(e))

    # 3. enable services in the target.
    for svc in SERVICES:
        _enable(["enable", svc])
    _enable(["--global", "enable", "libinput-gestures.service"])
    _enable(["enable", "devos-firstboot.service"])

    # 4. wheel sudoers rule.
    _write(os.path.join(root, "etc/sudoers.d/wheel"), WHEEL_SUDOERS, 0o440)

    # 5. mkinitcpio HOOKS: drop the live archiso hooks, write installed-system hooks.
    _rm(os.path.join(root, "etc/mkinitcpio.conf.d/archiso.conf"))
    _write(os.path.join(root, "etc/mkinitcpio.conf.d/devos.conf"), INSTALLED_HOOKS, 0o644)

    # 6. locale: uncomment en_US.UTF-8 then generate in the target.
    _uncomment_locale(os.path.join(root, "etc/locale.gen"))
    if libcalamares.utils.target_env_call(["locale-gen"]) != 0:
        return ("devossetup failed", "locale-gen failed in the target system.")

    # 7. compile the dconf system db (best-effort).
    if libcalamares.utils.target_env_call(["dconf", "update"]) != 0:
        libcalamares.utils.warning("devossetup: dconf update returned non-zero")

    return None
