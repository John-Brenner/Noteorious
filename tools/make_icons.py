"""Regenerates the built-in Noteorious icons in ../icons/.

Usage:  python tools/make_icons.py      (requires Pillow)

Each icon is drawn at 8x size, given a dark outline so it stays readable over
any game scene, and downsampled to 48x48 PNG with transparency. The addon
scales them to `icon_size` (24 px by default).
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 48
SCALE = 8
CANVAS = SIZE * SCALE
DARK = (22, 22, 28, 255)
OUT = Path(__file__).resolve().parent.parent / "icons"


def layers():
    base = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    detail = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    return base, detail, ImageDraw.Draw(base), ImageDraw.Draw(detail)


def finish(name, base, detail):
    # Outline: grow the silhouette and paint it dark underneath.
    alpha = base.split()[3]
    grown = alpha.filter(ImageFilter.MaxFilter(27))
    outline = Image.new("RGBA", base.size, DARK)
    outline.putalpha(grown)
    icon = Image.alpha_composite(outline, base)
    icon = Image.alpha_composite(icon, detail)
    icon = icon.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.mkdir(exist_ok=True)
    icon.save(OUT / f"{name}.png", optimize=True)


def warning():
    base, detail, b, d = layers()
    b.polygon([(192, 34), (360, 334), (24, 334)], fill=(255, 190, 40, 255))
    d.rounded_rectangle((172, 118, 212, 250), radius=18, fill=DARK)
    d.ellipse((168, 270, 216, 318), fill=DARK)
    finish("warning", base, detail)


def skull():
    base, detail, b, d = layers()
    bone = (240, 234, 218, 255)
    b.ellipse((62, 30, 322, 280), fill=bone)
    b.rounded_rectangle((112, 210, 272, 340), radius=30, fill=bone)
    d.ellipse((106, 128, 178, 206), fill=DARK)
    d.ellipse((206, 128, 278, 206), fill=DARK)
    d.polygon([(192, 210), (172, 252), (212, 252)], fill=DARK)
    for x in (150, 192, 234):
        d.rounded_rectangle((x - 9, 282, x + 9, 340), radius=8, fill=DARK)
    finish("skull", base, detail)


def info():
    base, detail, b, d = layers()
    b.ellipse((24, 24, 360, 360), fill=(60, 135, 245, 255))
    white = (255, 255, 255, 255)
    d.ellipse((164, 74, 220, 130), fill=white)
    d.rounded_rectangle((166, 158, 218, 312), radius=20, fill=white)
    finish("info", base, detail)


def note():
    base, detail, b, d = layers()
    b.polygon([(48, 40), (336, 40), (336, 262), (258, 340), (48, 340)], fill=(255, 225, 90, 255))
    d.polygon([(258, 340), (258, 262), (336, 262)], fill=(214, 176, 50, 255))
    for y in (120, 180, 240):
        d.rounded_rectangle((96, y - 9, 290 if y < 240 else 220, y + 9), radius=8, fill=DARK)
    finish("note", base, detail)


def reminder():
    base, detail, b, d = layers()
    gold = (255, 200, 60, 255)
    b.ellipse((172, 26, 212, 66), fill=gold)
    b.chord((96, 52, 288, 260), 180, 360, fill=gold)
    b.polygon([(96, 156), (288, 156), (318, 300), (66, 300)], fill=gold)
    b.rounded_rectangle((46, 284, 338, 318), radius=16, fill=gold)
    b.ellipse((160, 306, 224, 360), fill=gold)
    d.rounded_rectangle((70, 290, 314, 302), radius=6, fill=(214, 160, 30, 255))
    finish("reminder", base, detail)


def star():
    import math

    base, detail, b, d = layers()
    points = []
    for i in range(10):
        r = 176 if i % 2 == 0 else 74
        a = math.radians(-90 + i * 36)
        points.append((192 + r * math.cos(a), 206 + r * math.sin(a)))
    b.polygon(points, fill=(255, 215, 70, 255))
    finish("star", base, detail)


if __name__ == "__main__":
    for make in (warning, skull, info, note, reminder, star):
        make()
    print("icons written to", OUT)
