"""Path resolution for bundled assets (works in dev and PyInstaller)."""

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def resource_path(relative: str) -> Path:
    """Absolute path to a bundled resource (assets/..., etc.)."""
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        return Path(meipass) / relative
    return PROJECT_ROOT / relative
