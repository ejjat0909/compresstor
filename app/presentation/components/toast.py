"""Toast notifications: non-blocking, stacked top-right with slide/fade."""

from __future__ import annotations

from enum import Enum

from PySide6.QtCore import QEasingCurve, QPoint, QPropertyAnimation, Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QFrame, QGraphicsOpacityEffect, QHBoxLayout, QVBoxLayout, QWidget

from app.presentation.components.button import IconButton
from app.presentation.components.icons import IconLabel
from app.presentation.components.typography import NormalText, SecondaryText
from app.presentation.theme.registry import active_theme


class ToastVariant(str, Enum):
    SUCCESS = "success"
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"


_ICONS = {
    ToastVariant.SUCCESS: "circle-check",
    ToastVariant.ERROR: "alert-circle",
    ToastVariant.WARNING: "alert-triangle",
    ToastVariant.INFO: "info",
}

_DURATIONS = {
    ToastVariant.SUCCESS: 3600,
    ToastVariant.ERROR: 6500,
    ToastVariant.WARNING: 5000,
    ToastVariant.INFO: 4200,
}


class ToastWidget(QFrame):
    """One toast card. Painted manually so colors follow the theme."""

    def __init__(self, variant: ToastVariant, title: str, message: str, parent=None) -> None:
        super().__init__(parent)
        self._variant = variant
        self._title = title
        self._message = message
        self.setFixedWidth(360)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_DeleteOnClose)
        self._build()
        self._opacity_effect = QGraphicsOpacityEffect(self)
        self._opacity_effect.setOpacity(0.0)
        self.setGraphicsEffect(self._opacity_effect)
        active_theme().changed.connect(lambda _m: self.update())

    def _build(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(14, 12, 8, 12)
        layout.setSpacing(10)

        self._icon = IconLabel(_ICONS[self._variant], 18)
        layout.addWidget(self._icon, 0, Qt.AlignTop)

        texts = QVBoxLayout()
        texts.setSpacing(2)
        title = NormalText(self._title)
        title.setWordWrap(True)
        texts.addWidget(title)
        if self._message:
            message = SecondaryText(self._message)
            message.setWordWrap(True)
            texts.addWidget(message)
        layout.addLayout(texts, 1)

        self._close = IconButton("x", "Dismiss", size="iconSm", icon_size=13)
        self._close.clicked.connect(self.close)
        layout.addWidget(self._close, 0, Qt.AlignTop)

    # ------------------------------------------------------------------ #
    def colors(self) -> tuple[str, str]:
        p = active_theme().palette
        if self._variant == ToastVariant.SUCCESS:
            return p.success, p.success_soft
        if self._variant == ToastVariant.ERROR:
            return p.danger, p.danger_soft
        if self._variant == ToastVariant.WARNING:
            return p.warning, p.warning_soft
        return p.info, p.info_soft

    def paintEvent(self, event) -> None:
        accent, soft = self.colors()
        p = active_theme().palette
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = self.rect().adjusted(0, 0, -1, -1)
        painter.setBrush(QColor(p.card))
        painter.setPen(QColor(p.border))
        painter.drawRoundedRect(rect, 10, 10)
        # accent bar on the left
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(accent))
        painter.drawRoundedRect(0, 14, 3, self.height() - 28, 2, 2)
        painter.end()
        self._icon.set_color(accent)

    def fade_in(self, duration: int = 180) -> None:
        anim = QPropertyAnimation(self._opacity_effect, b"opacity", self)
        anim.setDuration(duration)
        anim.setStartValue(0.0)
        anim.setEndValue(1.0)
        anim.start(QPropertyAnimation.DeleteWhenStopped)

    def fade_out(self, duration: int = 200) -> None:
        anim = QPropertyAnimation(self._opacity_effect, b"opacity", self)
        anim.setDuration(duration)
        anim.setStartValue(1.0)
        anim.setEndValue(0.0)
        anim.finished.connect(self.close)
        anim.start(QPropertyAnimation.DeleteWhenStopped)


class ToastManager(QWidget):
    """Overlay widget that stacks toasts top-right of its parent window."""

    GAP = 10
    MARGIN = 16

    def __init__(self, parent: QWidget) -> None:
        super().__init__(parent)
        self._toasts: list[ToastWidget] = []
        self.setAttribute(Qt.WA_TransparentForMouseEvents, False)
        self.setAttribute(Qt.WA_StyledBackground, False)
        parent.installEventFilter(self)
        self._place_overlay()
        self.hide()

    # ------------------------------------------------------------------ #
    def show_toast(self, variant: ToastVariant, title: str, message: str = "",
                   duration: int | None = None) -> None:
        toast = ToastWidget(variant, title, message, self)
        toast.setObjectName("toast")
        self._toasts.append(toast)
        toast.show()
        toast.fade_in()
        if duration is None:
            duration = _DURATIONS[variant]
        QTimer.singleShot(duration, lambda t=toast: self._dismiss(t))
        self._restack()

    def success(self, title: str, message: str = "") -> None:
        self.show_toast(ToastVariant.SUCCESS, title, message)

    def error(self, title: str, message: str = "") -> None:
        self.show_toast(ToastVariant.ERROR, title, message)

    def warning(self, title: str, message: str = "") -> None:
        self.show_toast(ToastVariant.WARNING, title, message)

    def info(self, title: str, message: str = "") -> None:
        self.show_toast(ToastVariant.INFO, title, message)

    # ------------------------------------------------------------------ #
    def _dismiss(self, toast: ToastWidget) -> None:
        if toast not in self._toasts:
            return
        self._toasts.remove(toast)
        toast.fade_out()
        self._restack()

    def _restack(self) -> None:
        y = self.MARGIN
        for toast in self._toasts:
            target = QPoint(self.width() - toast.width() - self.MARGIN, y)
            if toast.pos() != target:
                anim = QPropertyAnimation(toast, b"pos", toast)
                anim.setDuration(220)
                anim.setEasingCurve(QEasingCurve.OutCubic)
                anim.setStartValue(toast.pos())
                anim.setEndValue(target)
                anim.start(QPropertyAnimation.DeleteWhenStopped)
            y += toast.height() + self.GAP

    def _place_overlay(self) -> None:
        parent = self.parentWidget()
        if parent:
            self.setGeometry(0, 0, parent.width(), parent.height())
            self.raise_()

    def eventFilter(self, obj, event) -> bool:
        if obj is self.parentWidget() and event.type() in (
            event.Type.Resize, event.Type.Show, event.Type.Move,
        ):
            self._place_overlay()
            self._restack()
        return super().eventFilter(obj, event)
