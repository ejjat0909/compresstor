"""Context menu helper: themed QMenu with icons."""

from __future__ import annotations

from typing import Callable, Optional

from PySide6.QtCore import QPoint, Qt
from PySide6.QtWidgets import QMenu, QWidget

from app.presentation.theme.registry import active_theme


class ContextMenu(QMenu):
    """A QMenu pre-styled by the global QSS, with icon helpers."""

    def add_action(self, text: str, icon: str | None, callback: Optional[Callable] = None,
                   enabled: bool = True, checked: bool | None = None):
        action = self.addAction(active_theme().icon(icon, size=15) if icon else self.icon(), text)
        action.setEnabled(enabled)
        if checked is not None:
            action.setCheckable(True)
            action.setChecked(checked)
        if callback:
            action.triggered.connect(lambda _=False, cb=callback: cb())
        return action

    def add_separator(self) -> None:
        self.addSeparator()


def show_context_menu(widget: QWidget, pos: QPoint, build: Callable[[ContextMenu], None]) -> None:
    """Build and show a context menu at *pos* (global coordinates)."""
    menu = ContextMenu(widget)
    build(menu)
    menu.exec(pos)
