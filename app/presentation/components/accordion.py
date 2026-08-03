"""Accordion: collapsible sections with smooth expand/collapse animation."""

from __future__ import annotations

from PySide6.QtCore import QEasingCurve, QPropertyAnimation, Qt
from PySide6.QtWidgets import QFrame, QHBoxLayout, QVBoxLayout, QWidget

from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.typography import CardTitle


class AccordionItem(QFrame):
    """A header row that toggles a body section."""

    def __init__(self, title: str, parent=None, initially_open: bool = False) -> None:
        super().__init__(parent)
        self.setProperty("ui", "cardSubtle")
        self._open = initially_open
        self._body: QWidget | None = None

        outer = QVBoxLayout(self)
        outer.setContentsMargins(12, 6, 12, 6)
        outer.setSpacing(0)

        header = QFrame()
        header.setCursor(Qt.PointingHandCursor)
        hl = QHBoxLayout(header)
        hl.setContentsMargins(4, 6, 4, 6)
        hl.setSpacing(8)
        self._chevron = Button("", ButtonVariant.GHOST, ButtonSize.ICON_SM, icon="chevron-right", icon_size=14)
        self._chevron.setEnabled(False)
        hl.addWidget(self._chevron)
        self._title = CardTitle(title)
        hl.addWidget(self._title)
        hl.addStretch(1)
        outer.addWidget(header)

        self._body_wrap = QWidget()
        self._body_wrap.setVisible(initially_open)
        self._body_layout = QVBoxLayout(self._body_wrap)
        self._body_layout.setContentsMargins(20, 2, 8, 8)
        self._body_layout.setSpacing(8)
        outer.addWidget(self._body_wrap)

        self._height_anim = QPropertyAnimation(self._body_wrap, b"maximumHeight", self)
        self._height_anim.setDuration(200)
        self._height_anim.setEasingCurve(QEasingCurve.OutCubic)

        header.mousePressEvent = self._on_header_press
        self._title.mousePressEvent = self._on_header_press
        self._chevron.mousePressEvent = self._on_header_press

    # ------------------------------------------------------------------ #
    def _on_header_press(self, event) -> None:
        if event.button() == Qt.LeftButton:
            self.toggle()
        event.accept()

    def body(self) -> QVBoxLayout:
        return self._body_layout

    def toggle(self) -> None:
        self._open = not self._open
        self._height_anim.stop()
        if self._open:
            self._body_wrap.setVisible(True)
            self._height_anim.setStartValue(0)
            self._height_anim.setEndValue(self._body_wrap.sizeHint().height())
            self._chevron.set_icon("chevron-down")
        else:
            self._height_anim.setStartValue(self._body_wrap.height())
            self._height_anim.setEndValue(0)
            self._height_anim.finished.connect(self._collapse_done)
            self._chevron.set_icon("chevron-right")
        self._height_anim.start()

    def _collapse_done(self) -> None:
        self._body_wrap.setVisible(False)

    def set_open(self, open_: bool) -> None:
        if open_ != self._open:
            self.toggle()


class Accordion(QVBoxLayout):
    """Vertical stack of AccordionItems."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setSpacing(8)
        self.setContentsMargins(0, 0, 0, 0)
        self._items: list[AccordionItem] = []

    def add_item(self, title: str, initially_open: bool = False) -> AccordionItem:
        item = AccordionItem(title, initially_open=initially_open)
        self.addWidget(item)
        self._items.append(item)
        return item
