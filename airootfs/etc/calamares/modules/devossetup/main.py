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

# mkinitcpio config for the installed system: no archiso/memdisk/pxe hooks.
# MODULES=(i915) forces EARLY KMS so the Intel framebuffer is up before Plymouth
# starts — lazy udev/autodetect loading lands after the boot-splash window, so on a
# real Mac the splash was black at boot (only showing at shutdown once i915 was up).
# The BINARIES line forces the plymouth `script` renderer into the initramfs (the
# hook bundles the theme files but not its engine). Canonical — mirrored by install.sh.
# `encrypt` is unconditional: this drop-in OVERRIDES whatever initcpiocfg writes to
# /etc/mkinitcpio.conf, so without it a LUKS install can never open its root
# (emergency shell on first boot); the hook is a no-op when the kernel cmdline
# carries no cryptdevice= (unencrypted installs are unaffected).
INSTALLED_HOOKS = (
    "MODULES=(i915)\n"
    "HOOKS=(base udev autodetect microcode modconf kms plymouth keyboard "
    "keymap consolefont block encrypt filesystems fsck)\n"
    "BINARIES=(/usr/lib/plymouth/script.so)\n"
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


def _ensure_sddm_wallpaper_perms(root):
    """Make /var/lib/devos/sddm-wallpaper.jpg wheel-writable + world-readable.

    The file is rsynced from the live system by copyairootfs; here we just assert
    the ownership/modes so the installed user's session helper
    (devos-sddm-wallpaper-sync) can mirror the desktop wallpaper into it with no
    elevation, while the unprivileged sddm greeter can still read it. setgid on
    the dir makes the helper's atomically-renamed temp files inherit the wheel
    group. Mirrored by install.sh. Best-effort: never fail the install for this.
    """
    d = os.path.join(root, "var/lib/devos")
    f = os.path.join(d, "sddm-wallpaper.jpg")
    try:
        os.makedirs(d, exist_ok=True)
        shutil.chown(d, group="wheel")
        os.chmod(d, 0o2775)
        if os.path.exists(f):
            shutil.chown(f, group="wheel")
            os.chmod(f, 0o664)
        # Per-user login avatars: devos-sddm-avatar-sync publishes ~/.face here
        # as <user>.face.icon and SDDM's FacesDir points at it. Same scheme.
        fdir = os.path.join(d, "faces")
        os.makedirs(fdir, exist_ok=True)
        shutil.chown(fdir, group="wheel")
        os.chmod(fdir, 0o2775)
    except (OSError, LookupError) as e:
        libcalamares.utils.warning("devossetup: sddm wallpaper perms: " + str(e))


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

    # 1b. Backfill skel into the created user's home. devossetup runs AFTER the
    # users module, and `useradd -m` SILENTLY skips the skel copy when the home
    # directory already exists (kept/reused /home partition from an earlier
    # install) — which strands the user without newer skel additions (machud +
    # its icons: "Failed to execute child process" on every media key).
    # --ignore-existing only fills gaps, never clobbers the user's own dotfiles
    # on a kept home. install.sh has the equivalent guarantee for its live
    # 'user' account (cp -aT skel -> home). Best-effort: never fail the install.
    username = libcalamares.globalstorage.value("username")
    if username:
        home = "/home/" + username
        if libcalamares.utils.target_env_call(
                ["rsync", "-a", "--ignore-existing", "/etc/skel/", home + "/"]) != 0:
            libcalamares.utils.warning("devossetup: skel backfill failed for " + home)
        elif libcalamares.utils.target_env_call(
                ["chown", "-R", "{0}:{0}".format(username), home]) != 0:
            libcalamares.utils.warning("devossetup: chown failed for " + home)

    # 2b. SDDM login wallpaper: ensure the per-machine file is wheel-writable +
    # world-readable (desktop session mirrors into it; sddm greeter reads it).
    _ensure_sddm_wallpaper_perms(root)

    # 3. enable services in the target.
    for svc in SERVICES:
        _enable(["enable", svc])
    _enable(["--global", "enable", "libinput-gestures.service"])
    _enable(["enable", "devos-firstboot.service"])

    # Display manager: the INSTALLED system shows the SDDM greeter. SDDM is NOT
    # enabled on the live ISO (that stays agetty->startx), so enable it here and
    # switch the default target to graphical so the greeter actually starts.
    _enable(["enable", "sddm"])
    _enable(["set-default", "graphical.target"])
    # Arch's Qt6 sddm daemon launches the Qt5 /usr/bin/sddm-greeter by default,
    # which exits 127 on DevOS (no Qt5 runtime). Point it at the Qt6 greeter.
    # (The pacman hook re-applies this after future sddm upgrades.)
    greeter = os.path.join(root, "usr/bin/sddm-greeter")
    try:
        if os.path.islink(greeter) or os.path.exists(greeter):
            os.remove(greeter)
        os.symlink("/usr/bin/sddm-greeter-qt6", greeter)
    except OSError as e:
        libcalamares.utils.warning("devossetup: sddm-greeter symlink failed: " + str(e))

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
