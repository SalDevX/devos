#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the DevOS Plymouth boot-splash assets (Pillow only, no network).

Produces, into airootfs/usr/share/plymouth/themes/devos/:
  * devos-logo.png       — the "devOS" wordmark (Geist-Light), pre-rendered so the
                           splash needs NO font in the initramfs (fc-match finds
                           none in early boot -> Image.Text draws nothing -> black
                           screen). Lowercase 'd', uppercase 'OS'.
  * bar_track_cap_l/r.png / bar_track_mid.png — pill progress-bar track (gray)
  * bar_fill_cap_l/r.png  / bar_fill_mid.png  — pill progress-bar fill  (near-white)

Caps are left/right semicircles (each rad×BAR_H) cut from one anti-aliased
circle; devos.script ABUTS them to a flat stretched mid (no overlap), so the
pill has clean rounded ends with no pinch at the joins AND no alpha stacking on
the semi-transparent track. Re-run after changing the wordmark
or BAR_H, then run gen-boot-splash.py to propagate the logo to the BIOS/GRUB
menu backgrounds.

Usage:  python3 tools/gen-plymouth-assets.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # devos/
THEME = os.path.join(ROOT, "airootfs/usr/share/plymouth/themes/devos")
FONT = os.path.join(THEME, "Geist-Light.ttf")

WORDMARK = "devOS"   # lowercase d (small-caps feel), uppercase OS
LOGO_PT = 56         # final wordmark size in px (smaller than the old ~83px mark)
SS = 6               # supersample factor for crisp anti-aliasing

BAR_H = 8            # pill height (px) — devos.script bar_h MUST match this
TRACK_ALPHA = 56     # ~0.22 -> gray track on the #111111 background
FILL_ALPHA = 242     # ~0.95 -> near-white fill

# LUKS passphrase dialog (pw_prompt.png + pw_bullet.png). Pre-rendered for the
# same reason as the wordmark: Image.Text draws nothing in the initramfs. The
# devos.script password callbacks swap the progress bar for this prompt + one
# bullet per typed character — without them `plymouth ask-for-password` (encrypt
# hook / systemd-cryptsetup) renders NOTHING and an encrypted boot looks hung.
PW_PROMPT = "Enter passphrase"
PW_PT = 20           # prompt size in px
PW_ALPHA = 200       # slightly dimmer than the wordmark
PW_BULLET_D = 12     # bullet dot diameter (px) — devos.script reads the PNG size


def _save(img, name):
    out = os.path.join(THEME, name)
    img.save(out)
    print("wrote", os.path.relpath(out, ROOT), f"{img.width}x{img.height}")


def gen_logo():
    font = ImageFont.truetype(FONT, LOGO_PT * SS)
    box = ImageDraw.Draw(Image.new("RGBA", (10, 10))).textbbox((0, 0), WORDMARK, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    big = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(big).text((-box[0], -box[1]), WORDMARK, font=font, fill=(255, 255, 255, 235))
    _save(big.resize((max(1, w // SS), max(1, h // SS)), Image.LANCZOS), "devos-logo.png")


def _caps(alpha):
    """Left + right semicircle caps (each rad×BAR_H) cut from one AA circle, so
    they abut the flat mid with no overlap -> no alpha stacking, no pinch."""
    d = BAR_H * SS
    big = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, d - 1, d - 1], fill=(255, 255, 255, alpha))
    circle = big.resize((BAR_H, BAR_H), Image.LANCZOS)
    rad = BAR_H // 2
    return circle.crop((0, 0, rad, BAR_H)), circle.crop((BAR_H - rad, 0, BAR_H, BAR_H))


def _strip(alpha):
    return Image.new("RGBA", (4, BAR_H), (255, 255, 255, alpha))


def gen_password_assets():
    font = ImageFont.truetype(FONT, PW_PT * SS)
    box = ImageDraw.Draw(Image.new("RGBA", (10, 10))).textbbox((0, 0), PW_PROMPT, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    big = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(big).text((-box[0], -box[1]), PW_PROMPT, font=font, fill=(255, 255, 255, PW_ALPHA))
    _save(big.resize((max(1, w // SS), max(1, h // SS)), Image.LANCZOS), "pw_prompt.png")

    d = PW_BULLET_D * SS
    big = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, d - 1, d - 1], fill=(255, 255, 255, FILL_ALPHA))
    _save(big.resize((PW_BULLET_D, PW_BULLET_D), Image.LANCZOS), "pw_bullet.png")


def main():
    gen_logo()
    gen_password_assets()
    tl, tr = _caps(TRACK_ALPHA)
    fl, fr = _caps(FILL_ALPHA)
    _save(tl, "bar_track_cap_l.png")
    _save(tr, "bar_track_cap_r.png")
    _save(fl, "bar_fill_cap_l.png")
    _save(fr, "bar_fill_cap_r.png")
    _save(_strip(TRACK_ALPHA), "bar_track_mid.png")
    _save(_strip(FILL_ALPHA), "bar_fill_mid.png")


if __name__ == "__main__":
    main()
