"""Breadcrumbs: navigation trail of clickable segments."""

from __future__ import annotations

from typing import Callable, Optional

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFrame, QHBoxLayout

from app.presentation.components.button import Button, ButtonVariant
from app.presentation.components.icons import IconLabel
from app.presentation.components.typography import MutedText


class Breadcrumbs(QFrame):
    """Row like: Home / Compression / History"""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._layout = QHBoxLayout(self)
        self._layout.setContentsMargins(0, 0, 0, 0)
        self._layout.setSpacing(6)
        self._segments: list[tuple[str, Optional[Callable[[], None]]]] = []

    def set_path(self, segments: list[tuple[str, Optional[Callable[[], None]]]]) -> None:
        """segments: [(label, callback_or_None), ...]"""
        self._segments = segments
        while self._layout.count():
            item = self._layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        for i, (label, callback) in enumerate(segments):
            if i > 0:
                chevron = IconLabel("chevron-right", 12)
                self._layout.addWidget(chevron)
            if callback is not None:
                link = Button(label, ButtonVariant.GHOST, size="sm")
                link.clicked.connect(callback)
                self._layout.addWidget(link)
            else:
                current = MutedText(label)
                self._layout.addWidget(current)
        self._layout.addStretch(1)
