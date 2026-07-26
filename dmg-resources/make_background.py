"""Regenerates dmg-resources/background.png used by the .github/workflows/release.yml
DMG packaging step. Run with: python3 dmg-resources/make_background.py

Renders at 2x internally for antialiasing quality, then downsamples to the
660x400 window size that --window-size / --icon coordinates in the workflow
assume.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SCALE = 2
W, H = 660 * SCALE, 400 * SCALE

BG_TOP = (13, 12, 18)
BG_BOTTOM = (7, 7, 10)
ACCENT = (198, 178, 245)       # lavender sparkle, dialed back from the app icon's (226,211,253)
ACCENT_SOFT = (150, 132, 200)

img = Image.new("RGB", (W, H), BG_BOTTOM)
draw = ImageDraw.Draw(img)

for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
    draw.line([(0, y), (W, y)], fill=(r, g, b))

glow = Image.new("L", (W, H), 0)
glow_draw = ImageDraw.Draw(glow)
cx, cy = W // 2, int(178 * SCALE)
max_r = int(120 * SCALE)
glow_draw.ellipse([cx - max_r, cy - max_r, cx + max_r, cy + max_r], fill=60)
glow = glow.filter(ImageFilter.GaussianBlur(int(55 * SCALE)))

purple_layer = Image.new("RGB", (W, H), ACCENT_SOFT)
img = Image.composite(purple_layer, img, glow)
draw = ImageDraw.Draw(img)

border_inset = int(1 * SCALE)
draw.rounded_rectangle(
    [border_inset, border_inset, W - border_inset, H - border_inset],
    radius=int(14 * SCALE),
    outline=(255, 255, 255, 40),
    width=1,
)

# Arrow bridging the app icon slot (x=180) and the Applications alias slot (x=480).
icon_y = int(180 * SCALE)
left_x = int(180 * SCALE)
right_x = int(480 * SCALE)
arrow_y = icon_y
shaft_start = left_x + int(95 * SCALE)
shaft_end = right_x - int(105 * SCALE)

arrow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
arrow_draw = ImageDraw.Draw(arrow_layer)
shaft_w = int(3 * SCALE)
arrow_draw.line([(shaft_start, arrow_y), (shaft_end, arrow_y)], fill=ACCENT + (220,), width=shaft_w)

head_len = int(16 * SCALE)
head_w = int(10 * SCALE)
tip = (shaft_end + int(14 * SCALE), arrow_y)
arrow_draw.polygon(
    [
        tip,
        (tip[0] - head_len, arrow_y - head_w),
        (tip[0] - head_len, arrow_y + head_w),
    ],
    fill=ACCENT + (220,),
)
img.paste(Image.alpha_composite(img.convert("RGBA"), arrow_layer).convert("RGB"), (0, 0))


def load_font(paths, size):
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


title_font = load_font(["/System/Library/Fonts/HelveticaNeue.ttc"], int(20 * SCALE))
sub_font = load_font(["/System/Library/Fonts/HelveticaNeue.ttc"], int(13 * SCALE))

draw = ImageDraw.Draw(img)

title = "Drag Erratly to Applications"
tw = draw.textlength(title, font=title_font)
draw.text(((W - tw) / 2, int(300 * SCALE)), title, font=title_font, fill=(240, 238, 245))

subtitle = "to finish installing"
sw = draw.textlength(subtitle, font=sub_font)
draw.text(((W - sw) / 2, int(332 * SCALE)), subtitle, font=sub_font, fill=(150, 148, 158))

final = img.resize((W // SCALE, H // SCALE), Image.LANCZOS)

out_path = os.path.join(os.path.dirname(__file__), "background.png")
final.save(out_path)
print("saved", out_path, final.size)
