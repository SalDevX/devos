# SPDX-License-Identifier: GPL-3.0-or-later
"""
DevOS Calamares job module: copyairootfs

Installs DevOS by rsyncing the running live system ("/") onto the target
partition — no internet, no pacstrap, every bundled package already present.
Replaces the built-in unpackfs flow for DevOS's live-copy model.

Native replacement for shellprocess@copy-airootfs + copy-airootfs.sh. The key
fix: rootMountPoint comes from Calamares globalStorage (the exact path the mount
module mounted), so this module and every built-in module that follows
(machineid, fstab, ...) operate on the SAME target. This deletes the entire
/mnt-vs-/tmp/calamares-root detection dance and the /run/devos-rootmountpoint
hand-off file that caused the 'chroot: /bin/sh not found' failures.

KEEP IN SYNC: devos/installer/install.sh mirrors the excludes / minimum-size /
dir-recreation below for the CLI path.
"""
import glob
import os
import re
import shutil
import subprocess

import libcalamares

# rsync exclude list — virtual filesystems, live-only mounts, /home (recreated
# empty for the target's own users). Canonical — mirrored by install.sh.
RSYNC_EXCLUDES = (
    "/proc/", "/sys/", "/run/", "/tmp/", "/mnt/", "/lost+found", "/home/",
)

# Minimum free space on the target. The live squashfs decompresses to ~8-9 GB;
# df on the archiso overlay is unreliable, so we require a flat 15 GiB
# (20 GB disk recommended). Canonical — mirrored by install.sh.
MIN_FREE_BYTES = 15 * 1024 ** 3

_GIB = 1024 ** 3
_PCT = re.compile(r"(\d+)%")


def _mkdir(path, mode):
    os.makedirs(path, exist_ok=True)
    os.chmod(path, mode)


def _rsync(root):
    """rsync live / -> target, feeding overall %% to the Calamares progress bar.

    Returns the rsync exit code.
    """
    cmd = ["rsync", "-aAXH", "--info=progress2"]
    cmd += ["--exclude=" + e for e in RSYNC_EXCLUDES]
    cmd += ["/", root + "/"]
    libcalamares.utils.debug("copyairootfs: " + " ".join(cmd))

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    buf = ""
    # --info=progress2 redraws the overall line with \r; split on \r and \n.
    while True:
        ch = proc.stdout.read(1)
        if not ch:
            break
        if ch in "\r\n":
            m = _PCT.search(buf)
            if m:
                libcalamares.job.setprogress(min(int(m.group(1)) / 100.0, 1.0))
            buf = ""
        else:
            buf += ch
    proc.wait()
    return proc.returncode


def _ensure_boot_kernel(root):
    """Populate the target /boot with the kernel image + microcode.

    archiso boots its kernel from the ISO, so the live /boot is empty and the
    rsync copied no kernel — mkinitcpio (-k) and the bootloader both need
    /boot/vmlinuz-linux-lts present. Prefer the image shipped in the modules
    tree (already on the target, guaranteed to match the installed modules);
    fall back to the ISO boot mount. Returns an error string or None.
    """
    boot = os.path.join(root, "boot")
    kernel_dst = os.path.join(boot, "vmlinuz-linux-lts")

    modules_kernels = glob.glob(os.path.join(root, "usr/lib/modules/*/vmlinuz"))
    iso_kernels = glob.glob("/run/archiso/bootmnt/*/boot/*/vmlinuz-linux-lts")
    if modules_kernels:
        shutil.copy2(modules_kernels[0], kernel_dst)
    elif iso_kernels:
        shutil.copy2(iso_kernels[0], kernel_dst)
    else:
        return ("Could not find the linux-lts kernel image to install into "
                "/boot (looked in /usr/lib/modules and the ISO boot mount).")
    libcalamares.utils.debug("copyairootfs: installed kernel -> " + kernel_dst)

    # Microcode ships only in /boot (empty on the live system) — pull it from
    # the ISO boot mount. Non-fatal: the system boots without it (no ucode).
    for uc in glob.glob("/run/archiso/bootmnt/*/boot/intel-ucode.img"):
        shutil.copy2(uc, os.path.join(boot, "intel-ucode.img"))
        libcalamares.utils.debug("copyairootfs: installed intel-ucode.img")
        break
    return None


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("Installation failed",
                "rootMountPoint is not set in globalStorage — the mount module "
                "did not run or failed to mount the target partition.")
    if not os.path.ismount(root):
        return ("Installation failed",
                "Target '{}' is not a mountpoint — the mount module failed.".format(root))
    libcalamares.utils.debug("copyairootfs: rootMountPoint=" + root)

    # Disk-space pre-flight.
    st = os.statvfs(root)
    avail = st.f_bavail * st.f_frsize
    if avail < MIN_FREE_BYTES:
        return ("Not enough disk space",
                "The target partition has only {:.1f} GB free, but DevOS needs at "
                "least {:.0f} GB (a 20 GB disk is recommended). Use a larger "
                "partition.".format(avail / _GIB, MIN_FREE_BYTES / _GIB))
    libcalamares.utils.debug(
        "copyairootfs: target has {:.1f} GB free".format(avail / _GIB))

    # Copy the live system.
    rc = _rsync(root)
    if rc != 0:
        return ("Installation failed",
                "Copying the system to the target failed (rsync exit {}). "
                "The disk may be full or have I/O errors.".format(rc))

    # Recreate the excluded virtual/runtime directories on the target.
    for d in ("proc", "sys", "run"):
        _mkdir(os.path.join(root, d), 0o755)
    _mkdir(os.path.join(root, "tmp"), 0o1777)
    _mkdir(os.path.join(root, "home"), 0o755)

    # Install the kernel + microcode into /boot — the live archiso /boot is
    # empty, so mkinitcpio and the bootloader would otherwise find no kernel.
    err = _ensure_boot_kernel(root)
    if err:
        return ("Installation failed", err)

    libcalamares.job.setprogress(1.0)
    libcalamares.utils.debug("copyairootfs: done")
    return None
