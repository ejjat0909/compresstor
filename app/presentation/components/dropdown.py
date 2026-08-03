"""Dropdown component (styled QComboBox)."""

from __future__ import annotations

from typing import Optional

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QComboBox, QFrame, QHBoxLayout, QLabel

from app.presentation.components.typography import MutedText


class Dropdown(QComboBox):
    """A shadcn-style select."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setCursor(Qt.PointingHandCursor)

    def add_options(self, items: list[str | tuple[str, str]]) -> None:
        """Accept ['label'] or [('value', 'label')] pairs."""
        for item in items:
            if isinstance(item, tuple):
                value, label = item
                self.addItem(label, userData=value)
            else:
                self.addItem(item, userData=item)

    def current_value(self) -> Optional[str]:
        return self.currentData()

    def set_value(self, value: str) -> bool:
        for i in range(self.count()):
            if self.itemData(i) == value:
                self.setCurrentIndex(i)
                return True
        return False


class FieldLabel(QFrame):
    """A labeled field: caption label above a control (stacked)."""

    def __init__(self, label: str, control, parent=None) -> None:
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        self._label = MutedText(label)
        self._label.setMinimumWidth(110)
        layout.addWidget(self._label)
        layout.addWidget(control, 1)
