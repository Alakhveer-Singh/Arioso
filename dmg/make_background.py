"""Draws the DMG window background (1x + 2x) in Arioso's black, white and slate palette,
with an arrow made of music notes pointing from the app to Applications."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os, sys

W, H = 660, 400                    # window content size in points
APP_X, APPS_X, ICON_Y = 170, 490, 190
OUT = os.path.dirname(os.path.abspath(__file__))

INK = (19, 24, 28)
AMBER = (78, 108, 124)
DIM = (78, 108, 124, 150)

# Arrow rows: (starting column, text). The middle row is the tip.
ROWS = [
    (16, "♪ ♪ ♪"),
    (18, "♪ ♪ ♪"),
    (0,  "your song, ♪ ♪ ♪ ♪ ♪ ♪"),
    (0,  "♪ #DRAG_TO_INSTALL ♪ ♪ ♪"),
    (0,  "word by word ♪ ♪ ♪ ♪ ♪"),
    (18, "♪ ♪ ♪"),
    (16, "♪ ♪ ♪"),
]
HIGHLIGHT = "DRAG_TO_INSTALL"


def render(scale):
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h), (246, 248, 249))

    # soft slate glows
    glow = Image.new("RGB", (w, h), (246, 248, 249))
    g = ImageDraw.Draw(glow)
    g.ellipse([w * .62, h * .05, w * 1.25, h * 1.05], fill=(200, 214, 222))
    g.ellipse([-w * .25, h * .45, w * .35, h * 1.3], fill=(222, 230, 235))
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(90 * scale)), .85)

    d = ImageDraw.Draw(img, "RGBA")
    size = 11 * scale
    mono = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", int(size))
    mono_b = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", int(size))
    try:
        mono_b.set_variation_by_name("Bold")
    except Exception:
        pass
    notes = ImageFont.truetype("/System/Library/Fonts/Apple Symbols.ttf", int(size * 1.25))

    adv = mono.getlength("M")
    line_h = size * 1.55
    cols = max(c + len(t) for c, t in ROWS)
    left = (APP_X + APPS_X) / 2 * scale - cols * adv / 2
    top = (ICON_Y - 8) * scale - len(ROWS) * line_h / 2

    for r, (col, text) in enumerate(ROWS):
        y = top + r * line_h
        hi_start = text.find(HIGHLIGHT)
        for i, ch in enumerate(text):
            x = left + (col + i) * adv
            if ch == " ":
                continue
            if ch == "♪":
                d.text((x + adv / 2, y + size * .55), ch, font=notes, fill=AMBER, anchor="mm")
            elif hi_start >= 0 and hi_start <= i < hi_start + len(HIGHLIGHT):
                d.text((x, y), ch, font=mono_b, fill=INK)
            else:
                d.text((x, y), ch, font=mono, fill=DIM)
    return img


if __name__ == "__main__":
    render(1).save(os.path.join(OUT, "background.png"))
    render(2).save(os.path.join(OUT, "background@2x.png"))
    print("wrote background.png and background@2x.png")
