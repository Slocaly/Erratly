"""Regenerates dmg-resources/background.png used by the .github/workflows/release.yml
DMG packaging step. Run with: python3 dmg-resources/make_background.py

Renders at 2x internally for antialiasing quality, then downsamples to the
660x400 window size that --window-size / --icon coordinates in the workflow
assume.
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SCALE = 2
W, H = 660 * SCALE, 400 * SCALE

PAPER = (246, 239, 216)        # matches the review panel and the landing page
INK = (32, 24, 15)
MUTED = (138, 127, 99)
ACCENT = (179, 57, 46)         # editor's red
RULE_SPACING = 31 * SCALE

img = Image.new("RGB", (W, H), PAPER)

# Ruled notebook lines, same rhythm as the landing page background.
rules = Image.new("RGBA", (W, H), (0, 0, 0, 0))
rules_draw = ImageDraw.Draw(rules)
for y in range(RULE_SPACING, H, RULE_SPACING):
    rules_draw.rectangle([0, y, W, y + SCALE - 1], fill=ACCENT + (28,))

# Faint paper grain, like DiffPanel's PaperView.
random.seed(7)
for _ in range(W * H // 40):
    x, y = random.randrange(W), random.randrange(H)
    rules_draw.point((x, y), fill=(random.choice([(0, 0, 0), (255, 255, 255)]) + (random.randint(4, 14),)))

img = Image.alpha_composite(img.convert("RGBA"), rules)
draw = ImageDraw.Draw(img)

# Arrow bridging the app icon slot (x=180) and the Applications alias slot (x=480).
icon_y = int(180 * SCALE)
left_x = int(180 * SCALE)
right_x = int(480 * SCALE)
arrow_y = icon_y
shaft_start = left_x + int(95 * SCALE)
shaft_end = right_x - int(105 * SCALE)

shaft_w = int(3 * SCALE)
draw.line([(shaft_start, arrow_y), (shaft_end, arrow_y)], fill=ACCENT, width=shaft_w)

head_len = int(16 * SCALE)
head_w = int(10 * SCALE)
tip = (shaft_end + int(14 * SCALE), arrow_y)
draw.polygon(
    [
        tip,
        (tip[0] - head_len, arrow_y - head_w),
        (tip[0] - head_len, arrow_y + head_w),
    ],
    fill=ACCENT,
)


def load_font(paths, size):
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


MONO = ["/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc"]


def mono(size, style):
    font = load_font(MONO, int(size * SCALE))
    try:
        font.set_variation_by_name(style)
    except Exception:
        pass
    return font


badge_font = mono(11, "Bold")
title_font = mono(18, "Bold")
sub_font = mono(12, "Regular")

# "INSTALL" tab in the top-left corner, like the landing page's "Try it" badge.
badge = "INSTALL"
bx, by = int(24 * SCALE), int(22 * SCALE)
pad_x, pad_y = int(10 * SCALE), int(4 * SCALE)
tracking = int(1.1 * SCALE)
badge_w = sum(draw.textlength(c, font=badge_font) for c in badge) + tracking * (len(badge) - 1)
ascent, descent = badge_font.getmetrics()
draw.rectangle([bx, by, bx + badge_w + pad_x * 2, by + ascent + descent + pad_y * 2], fill=INK)
cx = bx + pad_x
for c in badge:
    draw.text((cx, by + pad_y), c, font=badge_font, fill=PAPER)
    cx += draw.textlength(c, font=badge_font) + tracking

title = "Drag Erratly to Applications"
tw = draw.textlength(title, font=title_font)
draw.text(((W - tw) / 2, int(300 * SCALE)), title, font=title_font, fill=INK)

subtitle = "to finish installing"
sw = draw.textlength(subtitle, font=sub_font)
draw.text(((W - sw) / 2, int(332 * SCALE)), subtitle, font=sub_font, fill=MUTED)

final = img.convert("RGB").resize((W // SCALE, H // SCALE), Image.LANCZOS)

out_path = os.path.join(os.path.dirname(__file__), "background.png")
final.save(out_path)
print("saved", out_path, final.size)
