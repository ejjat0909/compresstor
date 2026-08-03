"""Icon helpers: lucide-style SVG icons rendered as QLabel pixmaps.

Icons are tinted from the theme palette so they follow light/dark mode and
the accent color automatically.
"""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel

from app.presentation.theme.registry import active_theme


class IconLabel(QLabel):
    """A label that shows a themed lucide icon."""

    def __init__(self, name: str, size: int = 16, color: str | None = None, parent=None) -> None:
        super().__init__(parent)
        self._name = name
        self._size = size
        self._color = color
        self.setFixedSize(size + 4, size + 4)
        self._apply()
        active_theme().changed.connect(lambda _m: self._safe_apply())

    def _safe_apply(self) -> None:
        try:
            self._apply()
        except RuntimeError:
            pass  # widget destroyed during teardown

    def set_icon(self, name: str) -> None:
        self._name = name
        try:
            self._apply()
        except RuntimeError:
            pass

    def set_color(self, color: str | None) -> None:
        self._color = color
        try:
            self._apply()
        except RuntimeError:
            pass

    def _apply(self) -> None:
        theme = active_theme()
        pix = theme.pixmap(self._name, self._color, self._size)
        self.setPixmap(pix)
        self.setAlignment(Qt.AlignCenter)
