"""Font resolution: bundle Inter, fall back to system fonts."""

from __future__ import annotations

import logging
import sys
from pathlib import Path

from PySide6.QtGui import QFont, QFontDatabase

from app.resources import resource_path

log = logging.getLogger(__name__)

_FONT_DIR = resource_path("assets/fonts")

FONT_FAMILY = "Inter"
_FALLBACKS = ["Segoe UI", "SF Pro Text", "Helvetica Neue", "Arial", "sans-serif"]

# Weights used across the app.
W_REGULAR = QFont.Weight.Normal
W_MEDIUM = QFont.Weight.Medium
W_SEMIBOLD = QFont.Weight.DemiBold
W_BOLD = QFont.Weight.Bold


def _bundled_font_files() -> list[Path]:
    if not _FONT_DIR.exists():
        return []
    return sorted(p for p in _FONT_DIR.iterdir() if p.suffix.lower() in (".ttf", ".otf", ".ttc"))


def load_fonts() -> str:
    """Register bundled fonts; returns the resolved family name."""
    family: str | None = None
    for font_file in _bundled_font_files():
        try:
            fid = QFontDatabase.addApplicationFont(str(font_file))
            if fid >= 0:
                families = QFontDatabase.applicationFontFamilies(fid)
                if families:
                    family = families[0]
                    break
        except Exception as exc:  # pragma: no cover
            log.warning("Failed to load font %s: %s", font_file.name, exc)
    return family or FONT_FAMILY


def resolve_family() -> str:
    """Return the best available family name for QSS font-family."""
    if sys.platform == "win32":
        return "Segoe UI"
    if sys.platform == "darwin":
        return "Inter, -apple-system, 'SF Pro Text', Helvetica Neue"
    return "Inter, 'Ubuntu', 'DejaVu Sans', sans-serif"


def app_font(base_pt: float = 13.0) -> QFont:
    """Default application font."""
    f = QFont()
    f.setFamilies([FONT_FAMILY] + _FALLBACKS)
    f.setPointSizeF(base_pt)
    f.setWeight(W_REGULAR)
    return f


def font(
    size_pt: float = 13.0,
    weight: int = W_REGULAR,
    italic: bool = False,
    letter_spacing: float = 0.0,
) -> QFont:
    f = QFont()
    f.setFamilies([FONT_FAMILY] + _FALLBACKS)
    f.setPointSizeF(size_pt)
    f.setWeight(weight)
    f.setItalic(italic)
    if letter_spacing:
        f.setLetterSpacing(QFont.AbsoluteSpacing, letter_spacing)
    return f
