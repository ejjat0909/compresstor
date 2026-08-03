"""Process-wide access to the active ThemeManager (set at startup)."""

from __future__ import annotations

from typing import Optional

_ACTIVE: Optional["ThemeManager"] = None  # noqa: F821


def set_active_theme(manager) -> None:
    global _ACTIVE
    _ACTIVE = manager


def active_theme():
    """Return the active ThemeManager. Raises if not initialized."""
    if _ACTIVE is None:
        raise RuntimeError("ThemeManager not initialized — call set_active_theme() first")
    return _ACTIVE
