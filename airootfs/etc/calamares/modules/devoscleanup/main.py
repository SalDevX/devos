# SPDX-License-Identifier: GPL-3.0-or-later
"""
DevOS Calamares job module: devoscleanup

Removes live-ISO-only artefacts from the freshly installed target so the
installed machine boots clean: the installer desktop shortcut, the Calamares
config tree, the passwordless-sudo drop-in, the autostart launchers, the
devos-calamares wrapper, the getty autologin drop-in, and the leftover live
'user' account (the live system is copied wholesale, so all of these would
otherwise leak onto the installed disk).

Native replacement for the former shellprocess@cleanup + cleanup.sh. Reads the
real target mount point from Calamares globalStorage (set by the mount module)
instead of the old /run/devos-rootmountpoint hand-off file, and surfaces a real
error dialog on failure instead of being swallowed by shellprocess YAML.
"""
import glob
import os
import shutil

import libcalamares

# Kernel params the installed system needs for the Plymouth graphical splash.
# Calamares' bootloader module writes the systemd-boot entries with no `splash`,
# so plymouthd starts but never leaves text mode -> black screen during boot
# (everything else — autologin, XFCE — still works). This job runs AFTER the
# bootloader module, so we append the params to every generated loader entry.
# Mirrors the live ISO cmdline (efiboot/.../01-devos-linux.conf) and the CLI
# installer's loader templates. KEEP IN SYNC with install.sh.
_SPLASH_PARAMS = ("quiet", "splash", "loglevel=3", "vt.global_cursor_default=0")

# Live-only files to delete from the installed target (relative to rootMountPoint).
_REMOVE_FILES = (
    "etc/skel/Desktop/install-devos.desktop",
    "etc/xdg/autostart/calamares.desktop",
    "etc/xdg/autostart/devos-trust-launcher.desktop",
    "etc/sudoers.d/zz-live-user",
    "usr/local/bin/devos-calamares",
    # Live autologin: agetty --autologin user on tty1. The live 'user' home is
    # not copied, so on the installed disk this would autologin into a missing
    # home and break startx. Removing it gives a normal login prompt.
    "etc/systemd/system/getty@tty1.service.d/autologin.conf",
)

# Live-only directories to delete recursively (relative to rootMountPoint).
_REMOVE_DIRS = (
    "etc/calamares",
)


def _rm_file(path):
    try:
        os.remove(path)
        libcalamares.utils.debug("devoscleanup: removed file " + path)
    except FileNotFoundError:
        pass


def _rm_tree(path):
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
        libcalamares.utils.debug("devoscleanup: removed tree " + path)


def _ensure_splash_cmdline(root):
    """Append the Plymouth splash params to every systemd-boot loader entry's
    `options` line (idempotent). Without `splash` the installed system boots to
    a black screen instead of the DevOS splash; with it Plymouth renders on real
    hardware and in VirtualBox/VMware alike (the KMS driver is pulled in by the
    autodetect+kms initramfs hooks at install time)."""
    entries = glob.glob(os.path.join(root, "boot/loader/entries/*.conf"))
    for entry in entries:
        try:
            with open(entry) as f:
                lines = f.readlines()
        except OSError:
            continue
        changed = False
        has_options = False
        for i, line in enumerate(lines):
            if line.startswith("options"):
                has_options = True
                tokens = line.split()
                for p in _SPLASH_PARAMS:
                    if p not in tokens:
                        tokens.append(p)
                        changed = True
                lines[i] = " ".join(tokens) + "\n"
        if not has_options:
            lines.append("options " + " ".join(_SPLASH_PARAMS) + "\n")
            changed = True
        if changed:
            with open(entry, "w") as f:
                f.writelines(lines)
            libcalamares.utils.debug("devoscleanup: splash cmdline -> " + entry)


def _purge_home_shortcuts(root):
    """Delete install-devos.desktop from every user home (mirrors the old find)."""
    home = os.path.join(root, "home")
    if not os.path.isdir(home):
        return
    for dirpath, _dirnames, filenames in os.walk(home):
        if "install-devos.desktop" in filenames:
            _rm_file(os.path.join(dirpath, "install-devos.desktop"))


def _purge_live_user(root):
    """Remove the leftover live 'user' account, unless the installer created a
    user actually named 'user'. The live account's home was excluded from the
    copy and it carries a known password — it must not ship on the install."""
    created = libcalamares.globalstorage.value("username")
    if created == "user":
        return  # the installed user IS 'user' — keep it
    # account exists only if it was copied in; userdel is a no-op-ish otherwise
    if libcalamares.utils.target_env_call(["id", "-u", "user"]) == 0:
        libcalamares.utils.target_env_call(["userdel", "user"])
        libcalamares.utils.debug("devoscleanup: removed leftover live 'user' account")
    # drop the now-empty getty override dir
    try:
        os.rmdir(os.path.join(root, "etc/systemd/system/getty@tty1.service.d"))
    except OSError:
        pass


def run():
    """Remove live-only artefacts from the installed system. None on success."""
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("devoscleanup failed",
                "rootMountPoint is not set in globalStorage — the mount module "
                "must run before devoscleanup.")

    libcalamares.utils.debug("devoscleanup: rootMountPoint=" + root)

    for rel in _REMOVE_FILES:
        _rm_file(os.path.join(root, rel))
    for rel in _REMOVE_DIRS:
        _rm_tree(os.path.join(root, rel))
    _purge_home_shortcuts(root)
    _purge_live_user(root)
    _ensure_splash_cmdline(root)

    return None
