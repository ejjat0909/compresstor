"""Modal dialogs: scrim overlay + centered card, and a confirmation dialog."""

from __future__ import annotations

from typing import Callable, Optional

from PySide6.QtCore import QEasingCurve, QPoint, QPropertyAnimation, Qt
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QFrame,
    QGraphicsOpacityEffect,
    QHBoxLayout,
    QVBoxLayout,
    QWidget,
)

from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.typography import NormalText, SectionTitle
from app.presentation.theme.registry import active_theme


class ModalOverlay(QFrame):
    """Full-window scrim that hosts a centered content card.

    Usage:
        overlay = ModalOverlay(window)
        overlay.open_card(card_widget, on_close=callback)
    """

    def __init__(self, parent: QWidget, dismissible: bool = True) -> None:
        super().__init__(parent)
        self._on_close: Optional[Callable[[], None]] = None
        self._dismissible = dismissible
        self._card: QWidget | None = None
        self.setAttribute(Qt.WA_TranslucentBackground)
        self._opacity = QGraphicsOpacityEffect(self)
        self._opacity.setOpacity(0.0)
        self.setGraphicsEffect(self._opacity)
        self.hide()
        parent.installEventFilter(self)

    # ------------------------------------------------------------------ #
    def open_card(self, card: QWidget, on_close: Optional[Callable[[], None]] = None,
                  width: int = 440) -> None:
        self._on_close = on_close
        self._card = card
        card.setParent(self)
        card.setFixedWidth(width)
        self._place_card()
        card.show()
        self.show()
        self.raise_()
        anim = QPropertyAnimation(self._opacity, b"opacity", self)
        anim.setDuration(180)
        anim.setStartValue(0.0)
        anim.setEndValue(1.0)
        anim.start(QPropertyAnimation.DeleteWhenStopped)
        slide = QPropertyAnimation(card, b"pos", card)
        slide.setDuration(200)
        slide.setEasingCurve(QEasingCurve.OutCubic)
        slide.setStartValue(card.pos() + QPoint(0, 14))
        slide.setEndValue(card.pos())
        slide.start(QPropertyAnimation.DeleteWhenStopped)
        self.setFocus()
        card.setFocus()

    def close_modal(self) -> None:
        if not self.isVisible():
            return
        card = self._card
        self._card = None
        anim = QPropertyAnimation(self._opacity, b"opacity", self)
        anim.setDuration(150)
        anim.setStartValue(1.0)
        anim.setEndValue(0.0)
        anim.finished.connect(self.hide)
        anim.start(QPropertyAnimation.DeleteWhenStopped)
        if card:
            card.deleteLater()
        if self._on_close:
            cb = self._on_close
            self._on_close = None
            cb()

    def is_open(self) -> bool:
        return self.isVisible()

    # ------------------------------------------------------------------ #
    def _place_card(self) -> None:
        parent = self.parentWidget()
        if parent:
            self.setGeometry(0, 0, parent.width(), parent.height())
        if self._card:
            x = (self.width() - self._card.width()) // 2
            y = (self.height() - self._card.height()) // 2 - 20
            self._card.move(max(x, 12), max(y, 12))

    def mousePressEvent(self, event) -> None:
        if self._dismissible and self._card and not self._card.geometry().contains(event.position().toPoint()):
            self.close_modal()
        super().mousePressEvent(event)

    def keyPressEvent(self, event) -> None:
        if event.key() == Qt.Key_Escape:
            self.close_modal()
        else:
            super().keyPressEvent(event)

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(active_theme().palette.overlay))
        painter.end()

    def eventFilter(self, obj, event) -> bool:
        if obj is self.parentWidget() and event.type() in (event.Type.Resize,):
            self._place_card()
        return super().eventFilter(obj, event)


class ModalCard(QFrame):
    """The card shell used inside a modal overlay."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setProperty("ui", "card")
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(24, 22, 24, 22)
        self._layout.setSpacing(14)

    def body(self) -> QVBoxLayout:
        return self._layout


class ConfirmDialog(ModalCard):
    """Confirmation dialog with optional destructive confirm action."""

    def __init__(
        self,
        title: str,
        message: str,
        confirm_text: str = "Confirm",
        cancel_text: str = "Cancel",
        danger: bool = False,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._confirmed = False

        self._layout.addWidget(SectionTitle(title))
        self._layout.addWidget(NormalText(message))

        actions = QHBoxLayout()
        actions.setSpacing(8)
        actions.addStretch(1)
        self._cancel = Button(cancel_text, ButtonVariant.OUTLINE)
        self._cancel.clicked.connect(lambda: self._finish(False))
        actions.addWidget(self._cancel)
        variant = ButtonVariant.DESTRUCTIVE if danger else ButtonVariant.PRIMARY
        self._confirm = Button(confirm_text, variant)
        self._confirm.setDefault(True)
        self._confirm.clicked.connect(lambda: self._finish(True))
        actions.addWidget(self._confirm)
        self._layout.addLayout(actions)

    def _finish(self, confirmed: bool) -> None:
        self._confirmed = confirmed
        overlay = self.parentWidget()
        if isinstance(overlay, ModalOverlay):
            overlay.close_modal()

    @property
    def confirmed(self) -> bool:
        return self._confirmed


def confirm(
    parent: QWidget,
    title: str,
    message: str,
    confirm_text: str = "Confirm",
    cancel_text: str = "Cancel",
    danger: bool = False,
    on_result: Optional[Callable[[bool], None]] = None,
) -> ModalOverlay:
    """Convenience: show a confirmation dialog, call on_result(confirmed)."""
    overlay = ModalOverlay(parent)
    dialog = ConfirmDialog(title, message, confirm_text, cancel_text, danger, overlay)
    if on_result:

        def wrapped():
            if dialog.confirmed:
                on_result(True)
        overlay._on_close = wrapped
    overlay.open_card(dialog)
    return overlay
