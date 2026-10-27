#!/usr/bin/env python3
"""Compose docs/images/ai-usage-hero.png from the demo screenshots (needs Pillow)."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

IMAGES = Path(__file__).resolve().parents[1] / "docs/images"
W, H = 1060, 1180


def gradient() -> Image.Image:
    top, bottom = (38, 30, 84), (12, 16, 36)
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    for y in range(H):
        t = y / H
        draw.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((W - 900, -300, W + 200, 700), fill=(120, 80, 220))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    return Image.blend(image, Image.composite(glow, image, glow.convert("L")), 0.35)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def main() -> None:
    canvas = gradient().convert("RGBA")
    bar_h = 64
    strip = Image.new("RGBA", (W, bar_h), (10, 10, 20, 150))
    canvas.alpha_composite(strip, (0, 0))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 26) if Path("/System/Library/Fonts/SFNS.ttf").exists() else ImageFont.load_default()
    draw.text((36, 18), "Finder   File   Edit", fill=(235, 235, 245, 230), font=font)

    indicator = Image.open(IMAGES / "ai-usage-menu-bar.png").convert("RGBA")
    scale = 44 / indicator.height
    indicator = indicator.resize((int(indicator.width * scale), 44), Image.LANCZOS)
    right = W - 250
    canvas.alpha_composite(rounded(indicator, 10), (right - indicator.width, 10))
    draw.text((W - 220, 18), "Tue 10:46", fill=(235, 235, 245, 230), font=font)

    panel = rounded(Image.open(IMAGES / "ai-usage-panel.png"), 36)
    px = right - panel.width + 110
    py = bar_h + 24
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((px, py + 24, px + panel.width, py + panel.height + 24), 36, fill=(0, 0, 0, 170))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(40)))
    canvas.alpha_composite(panel, (px, py))

    canvas.convert("RGB").crop((0, 0, W, py + panel.height + 90)).save(IMAGES / "ai-usage-hero.png", optimize=True)


if __name__ == "__main__":
    main()
