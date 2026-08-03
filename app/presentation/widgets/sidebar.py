"""Collapsible sidebar with animated nav items."""

from __future__ import annotations

from typing import Callable, Optional

from PySide6.QtCore import QEasingCurve, QPropertyAnimation, Qt, Signal
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout, QWidget

from app.presentation.components.button import Button, ButtonSize, ButtonVariant, IconButton
from app.presentation.components.icons import IconLabel
from app.presentation.components.typography import CaptionText
from app.presentation.theme.registry import active_theme

WIDTH_EXPANDED = 232
WIDTH_COLLAPSED = 66


class NavItem(QFrame):
    """A sidebar navigation entry with active state."""

    clicked = Signal()

    def __init__(self, icon: str, label: str, parent=None) -> None:
        super().__init__(parent)
        self._icon_name = icon
        self._label_text = label
        self._active = False
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedHeight(40)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 0, 10, 0)
        layout.setSpacing(10)
        self._icon = IconLabel(icon, 17)
        layout.addWidget(self._icon)
        self._label = QLabel(label)
        self._label.setStyleSheet("background: transparent;")
        layout.addWidget(self._label)
        layout.addStretch(1)
        active_theme().changed.connect(lambda _m: self.update())

    def set_active(self, active: bool) -> None:
        self._active = active
        self.update()

    def set_label_visible(self, visible: bool) -> None:
        self._label.setVisible(visible)

    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.LeftButton:
            self.clicked.emit()
        super().mousePressEvent(event)

    def paintEvent(self, event) -> None:
        p = active_theme().palette
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        if self._active:
            painter.setBrush(QColor(p.accent_soft))
            painter.setPen(Qt.NoPen)
            painter.drawRoundedRect(1, 2, self.width() - 2, self.height() - 4, 8, 8)
            # left indicator bar
            painter.setBrush(QColor(p.accent))
            painter.drawRoundedRect(0, 12, 3, self.height() - 24, 2, 2)
        elif self.underMouse():
            painter.setBrush(QColor(p.hover))
            painter.setPen(Qt.NoPen)
            painter.drawRoundedRect(1, 2, self.width() - 2, self.height() - 4, 8, 8)
        painter.end()
        color = p.accent if self._active else p.text_secondary
        self._icon.set_color(color)
        self._label.setStyleSheet(f"color: {color}; background: transparent; font-weight: 600;" if self._active
                                  else f"color: {p.text_secondary}; background: transparent; font-weight: 400;")


class Sidebar(QFrame):
    """Left navigation rail. Collapsible with a smooth width animation."""

    navigation_requested = Signal(str)  # page key

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._collapsed = False
        self._current = ""
        self._items: list[tuple[str, NavItem]] = []
        self.setFixedWidth(WIDTH_EXPANDED)
        self.setObjectName("sidebar")
        self._build()
        self._width_anim = QPropertyAnimation(self, b"maximumWidth", self)
        self._width_anim.setDuration(200)
        self._width_anim.setEasingCurve(QEasingCurve.OutCubic)

    # ------------------------------------------------------------------ #
    def _build(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(12, 16, 12, 14)
        outer.setSpacing(6)

        # logo row
        logo_row = QHBoxLayout()
        logo_row.setSpacing(10)
        self._logo_icon = IconLabel("layers", 22, "#ffffff")
        self._logo_badge = QFrame()
        self._logo_badge.setFixedSize(38, 38)
        self._logo_badge.setStyleSheet(
            "background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #3b82f6, stop:1 #2563eb);"
            "border-radius: 10px;"
        )
        lb = QVBoxLayout(self._logo_badge)
        lb.setContentsMargins(0, 0, 0, 0)
        lb.addWidget(self._logo_icon, 0, Qt.AlignCenter)
        logo_row.addWidget(self._logo_badge)
        self._wordmark = QLabel("Compresstor")
        self._wordmark.setStyleSheet(
            "font-size: 15pt; font-weight: 700; color: palette(text); background: transparent;"
        )
        logo_row.addWidget(self._wordmark)
        logo_row.addStretch(1)
        outer.addLayout(logo_row)
        outer.addSpacing(14)

        # nav section label
        self._nav_label = CaptionText("MENU")
        outer.addWidget(self._nav_label)
        outer.addSpacing(2)

        self._nav_container = QVBoxLayout()
        self._nav_container.setSpacing(2)
        outer.addLayout(self._nav_container, 1)

        # bottom controls
        self._settings_item = self._add_item("settings", "Settings", "settings")
        outer.addWidget(self._settings_item)

        collapse_row = QHBoxLayout()
        collapse_row.setSpacing(8)
        self._collapse_btn = IconButton("panel-left", "Collapse sidebar", size="icon", icon_size=16)
        self._collapse_btn.clicked.connect(self.toggle_collapse)
        collapse_row.addWidget(self._collapse_btn)
        self._collapse_label = QLabel("Collapse")
        self._collapse_label.setStyleSheet("color: palette(text); background: transparent;")
        collapse_row.addWidget(self._collapse_label)
        collapse_row.addStretch(1)
        outer.addLayout(collapse_row)

    def _add_item(self, key: str, label: str, icon: str) -> NavItem:
        item = NavItem(icon, label)
        item.clicked.connect(lambda: self._on_item(key))
        self._nav_container.addWidget(item)
        self._items.append((key, item))
        return item

    def add_page(self, key: str, label: str, icon: str) -> None:
        """Add a page entry (inserted before the settings item)."""
        idx = self._nav_container.indexOf(self._settings_item)
        item = NavItem(icon, label)
        item.clicked.connect(lambda: self._on_item(key))
        self._nav_container.insertWidget(idx, item)
        self._items.insert(len(self._items) - 1, (key, item))

    def _on_item(self, key: str) -> None:
        self.set_current(key)
        self.navigation_requested.emit(key)

    def set_current(self, key: str) -> None:
        self._current = key
        for k, item in self._items:
            item.set_active(k == key)

    # ------------------------------------------------------------------ #
    def toggle_collapse(self) -> None:
        self._collapsed = not self._collapsed
        self._width_anim.stop()
        self._width_anim.setStartValue(self.width())
        self._width_anim.setEndValue(WIDTH_COLLAPSED if self._collapsed else WIDTH_EXPANDED)
        self._width_anim.start()
        show = not self._collapsed
        for _, item in self._items:
            item.set_label_visible(show)
        self._wordmark.setVisible(show)
        self._nav_label.setVisible(show)
        self._collapse_label.setVisible(show)

    def set_collapsed(self, collapsed: bool) -> None:
        if collapsed != self._collapsed:
            self.toggle_collapse()

    def is_collapsed(self) -> bool:
        return self._collapsed
