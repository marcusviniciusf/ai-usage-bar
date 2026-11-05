#!/usr/bin/env python3
"""Compose docs/images/ai-usage-social.png (1280x640) for the GitHub social preview.

Needs Pillow. Run with a Python that has it, for example the bundled runtime:
  python3 scripts/render_social_preview.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

IMAGES = Path(__file__).resolve().parents[1] / "docs/images"
W, H = 1280, 640
TITLE = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 68)
try:
    TITLE.set_variation_by_name("Bold")
except OSError:
    pass
BODY = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 26)
SMALL = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 19)
TINY = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 16)

BG_TOP, BG_BOTTOM = (20, 22, 30), (8, 9, 13)
ACCENT = (124, 140, 255)
MUTED = (160, 166, 184)
WHITE = (240, 241, 247)


def background() -> Image.Image:
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    for y in range(H):
        t = y / H
        draw.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((W - 520, -320, W + 220, 420), fill=(70, 58, 160))
    glow = glow.filter(ImageFilter.GaussianBlur(170))
    return Image.blend(image, Image.composite(glow, image, glow.convert("L")), 0.32)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def main() -> None:
    canvas = background().convert("RGBA")

    icon = Image.open(IMAGES / "ai-usage-icon.png").convert("RGBA")
    icon = icon.resize((104, 104), Image.Resampling.LANCZOS)
    canvas.alpha_composite(rounded(icon, 24), (96, 92))

    draw = ImageDraw.Draw(canvas)
    draw.text((96, 226), "AI Usage", font=TITLE, fill=WHITE)
    draw.text((98, 316), "Spend and quota for your AI coding tools", font=BODY, fill=MUTED)
    draw.text((98, 360), "Cursor · Claude Code · OpenCode · Codex · DeepSeek", font=SMALL, fill=ACCENT)
    draw.text((98, 520), "macOS 14+  ·  native  ·  no login  ·  no telemetry", font=TINY, fill=(120, 126, 146))

    panel = Image.open(IMAGES / "ai-usage-panel.png").convert("RGBA")
    height = 600
    width = round(panel.width * height / panel.height)
    panel = panel.resize((width, height), Image.Resampling.LANCZOS)
    panel = rounded(panel, 26)

    shadow = Image.new("RGBA", (width + 80, height + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((40, 40, 40 + width, 40 + height), 30, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    x, y = W - width - 84, 20
    canvas.alpha_composite(shadow, (x - 40, y - 40 + 10))
    canvas.alpha_composite(panel, (x, y))

    output = IMAGES / "ai-usage-social.png"
    canvas.convert("RGB").save(output, optimize=True)
    print(f"Rendered {output}")


if __name__ == "__main__":
    main()
