#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the DevOS boot-menu splash images from the shared brand assets.

Produces:
  * syslinux/splash.png   640x480  — BIOS boot menu background (vesamenu.c32)
  * grub/background.png   1920x1080 — UEFI GRUB menu background (when wired up)

Both reuse the same brand as the Plymouth theme: the pre-rendered DevOS wordmark
(devos-logo.png) on the #111111 background (the same SetBackgroundTopColor the
Plymouth script uses). Re-run after changing the logo. Pillow only — no network,
no API cost.

Usage:  python3 tools/gen-boot-splash.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # devos/
THEME = os.path.join(ROOT, "airootfs/usr/share/plymouth/themes/devos")
LOGO = os.path.join(THEME, "devos-logo.png")
FONT = os.path.join(THEME, "Geist-Light.ttf")

BG = (17, 17, 17)  # #111111 — matches Plymouth SetBackgroundTopColor(0.067,...)
FG = (255, 255, 255)


def _wordmark(target_width):
    """Return an RGBA wordmark scaled so its width == target_width.

    Prefers the pre-rendered devos-logo.png (no font dependency); falls back to
    rendering "DevOS" with Geist-Light if the logo is missing."""
    if os.path.isfile(LOGO):
        logo = Image.open(LOGO).convert("RGBA")
        h = round(logo.height * target_width / logo.width)
        return logo.resize((target_width, h), Image.LANCZOS)
    # Fallback: render the wordmark from the font.
    size = round(target_width / 4.2)
    font = ImageFont.truetype(FONT, size) if os.path.isfile(FONT) \
        else ImageFont.load_default()
    tmp = Image.new("RGBA", (target_width, size * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    box = d.textbbox((0, 0), "DevOS", font=font)
    img = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((-box[0], -box[1]), "DevOS",
                             font=font, fill=FG + (230,))
    return img


def _compose(w, h, logo_w, logo_y_frac, out):
    """Dark canvas with the wordmark centered horizontally at logo_y_frac."""
    canvas = Image.new("RGBA", (w, h), BG + (255,))
    mark = _wordmark(logo_w)
    x = (w - mark.width) // 2
    y = round(h * logo_y_frac)
    canvas.alpha_composite(mark, (x, y))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.convert("RGB").save(out)  # flatten: bootloaders dislike alpha
    print("wrote", os.path.relpath(out, ROOT), f"{w}x{h}")


def main():
    # BIOS: wordmark in the upper third so the vesamenu box (VSHIFT) sits below.
    _compose(640, 480, 360, 0.12, os.path.join(ROOT, "syslinux/splash.png"))
    # UEFI/GRUB: larger wordmark, upper third, full-HD canvas.
    _compose(1920, 1080, 760, 0.18, os.path.join(ROOT, "grub/background.png"))


if __name__ == "__main__":
    main()
