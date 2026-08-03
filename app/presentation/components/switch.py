"""Switch component: custom-painted toggle with a smooth slide animation."""

from __future__ import annotations

from PySide6.QtCore import Property, QEasingCurve, QPointF, Qt, QVariantAnimation
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QAbstractButton

from app.presentation.theme.registry import active_theme


class Switch(QAbstractButton):
    """A macOS-style switch (checked state animates the knob)."""

    def __init__(self, checked: bool = False, parent=None) -> None:
        super().__init__(parent)
        self._checked = checked
        self._knob_pos = 1.0 if checked else 0.0
        self._anim = QVariantAnimation(self)
        self._anim.setDuration(160)
        self._anim.setEasingCurve(QEasingCurve.OutCubic)
        self._anim.valueChanged.connect(self._on_tick)
        self.setCheckable(True)
        self.setChecked(checked)
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(40, 22)
        active_theme().changed.connect(lambda _m: self.update())

    def _on_tick(self, value) -> None:
        self._knob_pos = float(value)
        self.update()

    def setChecked(self, checked: bool) -> None:  # noqa: N802 (Qt casing)
        super().setChecked(checked)
        if self._anim.state() == QVariantAnimation.Running:
            self._anim.stop()
        self._anim.setStartValue(self._knob_pos)
        self._anim.setEndValue(1.0 if checked else 0.0)
        self._anim.start()

    def paintEvent(self, event) -> None:
        theme = active_theme()
        p = theme.palette
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        track = QColor(p.accent) if self.isChecked() else QColor(p.border_strong)
        if not self.isEnabled():
            track = QColor(p.border_soft if not self.isChecked() else p.border_strong)
        painter.setPen(Qt.NoPen)
        painter.setBrush(track)
        painter.drawRoundedRect(1, 1, self.width() - 2, self.height() - 2, self.height() / 2, self.height() / 2)

        knob_radius = (self.height() - 6) / 2
        max_x = self.width() - 3 - knob_radius
        x = 3 + knob_radius + self._knob_pos * (max_x - (3 + knob_radius))
        painter.setBrush(QColor("#ffffff"))
        painter.drawEllipse(QPointF(x, self.height() / 2), knob_radius, knob_radius)
        painter.end()
