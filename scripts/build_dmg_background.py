#!/usr/bin/env python3
"""Render the dark background image used by the install DMG window.

Uses the bundled Inter font so the DMG matches the app's dark theme.
Output: a 660x400 PNG (the classic Finder DMG window client area).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "assets" / "fonts"

# Match the app's dark palette (slate-950 -> slate-900 subtle diagonal).
_BG_TOP = (2, 6, 23)
_BG_BOTTOM = (15, 22, 37)
_ACCENT = (59, 130, 246)
_TEXT = (241, 245, 249)
_MUTED = (100, 116, 139)


def _find_font(weight: int) -> str:
    for name in ("Inter", f"inter-{weight}", f"Inter-{weight}"):
        for ext in (".ttf", ".otf"):
            p = FONT_DIR / f"{name}{ext}"
            if p.exists():
                return str(p)
    # fall back to the first Inter ttf we can find
    matches = sorted(FONT_DIR.glob("*.ttf")) + sorted(FONT_DIR.glob("*.otf"))
    return str(matches[0]) if matches else ""


def build(out: Path, version: str) -> None:
    w, h = 660, 400
    img = Image.new("RGB", (w, h), _BG_TOP)
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        r = int(_BG_TOP[0] + (_BG_BOTTOM[0] - _BG_TOP[0]) * t)
        g = int(_BG_TOP[1] + (_BG_BOTTOM[1] - _BG_TOP[1]) * t)
        b = int(_BG_TOP[2] + (_BG_BOTTOM[2] - _BG_TOP[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    d = ImageDraw.Draw(img)

    light = ImageFont.truetype(_find_font(700), 40)
    name = ImageFont.truetype(_find_font(400), 22)
    small = ImageFont.truetype(_find_font(400), 16)

    d.text((w / 2, 88), "Compresstor", font=light, fill=_TEXT, anchor="mm")
    d.text((w / 2, 130), f"version {version}", font=name, fill=_MUTED, anchor="mm")

    accent = Image.new("RGBA", (w, 2), (*_ACCENT, 255))
    img.paste(accent, (0, int(h * 0.46)), accent)

    d.text((w / 2, 226), "Drag to your Applications folder to install", font=small, fill=_TEXT, anchor="mm")
    d.text((w / 2, 258), "or double-click the app", font=small, fill=_MUTED, anchor="mm")

    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--version", default="1.0.0")
    a = ap.parse_args()
    build(a.out, a.version)
    print(f"wrote {a.out}")