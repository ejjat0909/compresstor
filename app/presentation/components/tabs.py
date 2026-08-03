"""Tab component (styled QTabWidget)."""

from __future__ import annotations

from PySide6.QtWidgets import QTabWidget, QWidget


class Tabs(QTabWidget):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setDocumentMode(True)
        self.setTabPosition(QTabWidget.North)
        self.setMovable(False)

    def add_page(self, widget: QWidget, title: str) -> int:
        return self.addTab(widget, title)

    def set_page_title(self, index: int, title: str) -> None:
        self.setTabText(index, title)
