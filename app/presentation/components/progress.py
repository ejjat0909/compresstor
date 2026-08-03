"""Progress bar with smooth animated value updates."""

from __future__ import annotations

from enum import Enum

from PySide6.QtCore import QEasingCurve, QPropertyAnimation, Qt
from PySide6.QtWidgets import QProgressBar


class ProgressVariant(str, Enum):
    PRIMARY = "primary"
    SUCCESS = "success"
    DANGER = "danger"


class ProgressBar(QProgressBar):
    """Animated progress bar (values tween between updates)."""

    def __init__(self, variant: ProgressVariant | str = ProgressVariant.PRIMARY, parent=None) -> None:
        super().__init__(parent)
        self.setProperty("ui", str(variant))
        self.setRange(0, 100)
        self.setValue(0)
        self.setTextVisible(False)
        self.setFixedHeight(8)
        self._anim = QPropertyAnimation(self, b"value", self)
        self._anim.setDuration(220)
        self._anim.setEasingCurve(QEasingCurve.OutCubic)

    def set_progress(self, value: float) -> None:
        """Animate to *value* (0..1 or 0..100)."""
        v = int(value * 100) if value <= 1.0 else int(value)
        v = max(0, min(100, v))
        self._anim.stop()
        self._anim.setStartValue(self.value())
        self._anim.setEndValue(v)
        self._anim.start()

    def set_success(self) -> None:
        self.setProperty("ui", "success")
        self.style().unpolish(self)
        self.style().polish(self)

    def set_danger(self) -> None:
        self.setProperty("ui", "danger")
        self.style().unpolish(self)
        self.style().polish(self)
