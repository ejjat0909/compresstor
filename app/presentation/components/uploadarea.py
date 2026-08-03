"""Drag & drop upload area with animated hover/drag-over states."""

from __future__ import annotations

from typing import Callable, Optional

from PySide6.QtCore import Property, QEasingCurve, QPropertyAnimation, Qt, Signal
from PySide6.QtGui import QColor, QDragEnterEvent, QDragLeaveEvent, QDropEvent, QPainter
from PySide6.QtWidgets import QFileDialog, QFrame, QHBoxLayout, QVBoxLayout

from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.icons import IconLabel
from app.presentation.components.typography import CaptionText, NormalText, SecondaryText
from app.presentation.theme.palette import hex_to_rgba
from app.presentation.theme.registry import active_theme

SUPPORTED_FILTERS = "PDF (*.pdf);;Images (*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff *.gif);;All Files (*)"


class UploadArea(QFrame):
    """Large drop target. Emits files_dropped with a list of paths."""

    files_dropped = Signal(list)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._drag_over = False
        self._pulse = 0.0
        self.setAcceptDrops(True)
        self.setMinimumHeight(210)
        self.setCursor(Qt.PointingHandCursor)
        self._build()
        self._setup_animations()
        active_theme().changed.connect(lambda _m: self.update())

    # ------------------------------------------------------------------ #
    def _build(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(6)
        layout.setAlignment(Qt.AlignCenter)

        self._icon = IconLabel("upload-cloud", 44)
        layout.addWidget(self._icon, 0, Qt.AlignHCenter)

        self._title = NormalText("Drag & Drop Files Here")
        self._title.setAlignment(Qt.AlignCenter)
        layout.addWidget(self._title)

        self._sub = SecondaryText("or")
        self._sub.setAlignment(Qt.AlignCenter)
        layout.addWidget(self._sub)

        browse = Button("Browse Files", ButtonVariant.SECONDARY, ButtonSize.SM, icon="folder-open", icon_size=14)
        browse.clicked.connect(self._browse)
        layout.addWidget(browse, 0, Qt.AlignHCenter)

        self._hint = CaptionText("Supports PDF, JPG, PNG, WebP, BMP, TIFF, GIF")
        self._hint.setAlignment(Qt.AlignCenter)
        layout.addWidget(self._hint)

    def _setup_animations(self) -> None:
        self._drag_anim = QPropertyAnimation(self, b"pulse", self)
        self._drag_anim.setDuration(260)
        self._drag_anim.setEasingCurve(QEasingCurve.OutCubic)

    # ------------------------------------------------------------------ #
    @Property(float)
    def pulse(self) -> float:
        return self._pulse

    @pulse.setter
    def pulse(self, value: float) -> None:
        self._pulse = value
        self.update()

    def _set_drag_state(self, dragging: bool) -> None:
        self._drag_over = dragging
        self._drag_anim.stop()
        self._drag_anim.setStartValue(self._pulse)
        self._drag_anim.setEndValue(1.0 if dragging else 0.0)
        self._drag_anim.start()

    # ------------------------------------------------------------------ #
    def _browse(self) -> None:
        paths, _ = QFileDialog.getOpenFileNames(
            self, "Select files to compress", "", SUPPORTED_FILTERS
        )
        if paths:
            self.files_dropped.emit(paths)

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self._set_drag_state(True)

    def dragLeaveEvent(self, event: QDragLeaveEvent) -> None:
        self._set_drag_state(False)
        event.accept()

    def dropEvent(self, event: QDropEvent) -> None:
        self._set_drag_state(False)
        paths = [u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile()]
        if paths:
            self.files_dropped.emit(paths)
        event.acceptProposedAction()

    def paintEvent(self, event) -> None:
        theme = active_theme()
        p = theme.palette
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        active = self._drag_over
        border_color = QColor(p.accent if active else p.border)
        if active:
            border_color.setAlphaF(0.5 + 0.5 * self._pulse)
        fill = QColor(p.accent_soft if active else hex_to_rgba(p.accent, 0.02))
        fill.setAlphaF(0.5 * self._pulse if active else 0.15)

        rect = self.rect().adjusted(1, 1, -1, -1)
        painter.setBrush(fill)
        pen_width = 1.6 if active else 1.0
        painter.setPen(QColor(border_color))
        painter.drawRoundedRect(rect, 14, 14)
        if active:
            # inner highlight ring
            inner = rect.adjusted(5, 5, -5, -5)
            ring = QColor(p.accent)
            ring.setAlphaF(0.25 * self._pulse)
            painter.setPen(ring)
            painter.drawRoundedRect(inner, 10, 10)
        painter.end()

        # theme the icon/title when dragging
        self._icon.set_color(p.accent if active else None)
        self._title.setStyleSheet(
            f"color: {p.accent if active else p.text}; background: transparent;"
        )
