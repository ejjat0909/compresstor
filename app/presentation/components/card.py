"""Card component with a subtle border-deepening hover state.

No graphics effects here: rendering a widget through QGraphicsEffect drops
QSS backgrounds (Qt offscreen-render bug), and the design brief prefers
subtle borders over shadows anyway.
"""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFrame, QHBoxLayout, QVBoxLayout

from app.presentation.theme.registry import active_theme


class Card(QFrame):
    """A rounded panel with a thin border; border deepens on hover."""

    def __init__(self, title: str | None = None, subtle: bool = False, parent=None) -> None:
        super().__init__(parent)
        self.setProperty("ui", "cardSubtle" if subtle else "card")
        self.setAttribute(Qt.WA_Hover, True)
        self._title = title
        self._build()
        active_theme().changed.connect(lambda _m: self._on_theme_changed())

    def _on_theme_changed(self) -> None:
        try:
            self._restyle()
        except RuntimeError:
            pass  # widget destroyed during teardown

    # ------------------------------------------------------------------ #
    def _build(self) -> None:
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(20, 18, 20, 18)
        self._layout.setSpacing(12)
        if self._title:
            from app.presentation.components.typography import CardTitle

            header = QFrame()
            header.setAttribute(Qt.WA_TransparentForMouseEvents, True)
            hl = QHBoxLayout(header)
            hl.setContentsMargins(0, 0, 0, 0)
            hl.setSpacing(8)
            hl.addWidget(CardTitle(self._title))
            hl.addStretch(1)
            self._layout.addWidget(header)

    # ------------------------------------------------------------------ #
    def enterEvent(self, event) -> None:
        self._set_hover(True)
        super().enterEvent(event)

    def leaveEvent(self, event) -> None:
        self._set_hover(False)
        super().leaveEvent(event)

    def _set_hover(self, hovered: bool) -> None:
        self.setProperty("hover", hovered)
        self._restyle()

    def _restyle(self) -> None:
        self.style().unpolish(self)
        self.style().polish(self)
        self.update()

    def body(self) -> QVBoxLayout:
        return self._layout
