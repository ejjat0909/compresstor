"""Badge component with semantic variants."""

from __future__ import annotations

from enum import Enum

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QFrame, QHBoxLayout

from app.presentation.components.icons import IconLabel
from app.presentation.components.typography import CaptionText
from app.presentation.theme.registry import active_theme


class BadgeVariant(str, Enum):
    DEFAULT = "default"
    SECONDARY = "secondary"
    SUCCESS = "success"
    WARNING = "warning"
    DANGER = "danger"
    INFO = "info"
    OUTLINE = "outline"


class Badge(QFrame):
    """Small rounded pill with a tinted background, icon and label."""

    def __init__(self, text: str = "", variant: BadgeVariant | str = BadgeVariant.DEFAULT,
                 icon: str | None = None, parent=None) -> None:
        super().__init__(parent)
        self._variant = self._normalize(variant)
        self._icon_name = icon
        self._label: CaptionText | None = None
        self._icon: IconLabel | None = None
        self.setAttribute(Qt.WA_TranslucentBackground)
        self._build(text)
        active_theme().changed.connect(lambda _m: self._apply_colors())

    @staticmethod
    def _normalize(variant: BadgeVariant | str) -> str:
        """str() of a str-Enum returns 'BadgeVariant.SUCCESS'; we want 'success'."""
        return variant.value if isinstance(variant, BadgeVariant) else str(variant)

    def _build(self, text: str) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 3, 9, 3)
        layout.setSpacing(5)
        if self._icon_name:
            self._icon = IconLabel(self._icon_name, 12)
            layout.addWidget(self._icon)
        self._label = CaptionText(text)
        layout.addWidget(self._label)
        self._apply_colors()

    def set_text(self, text: str) -> None:
        if self._label:
            self._label.setText(text)

    def set_variant(self, variant: BadgeVariant | str) -> None:
        self._variant = self._normalize(variant)
        self._apply_colors()
        self.update()

    def set_icon(self, name: str | None) -> None:
        self._icon_name = name
        if name and self._icon:
            self._icon.set_icon(name)
        elif self._icon:
            self._icon.hide()
        self._apply_colors()

    # ------------------------------------------------------------------ #
    def _colors(self) -> tuple[str, str]:
        p = active_theme().palette
        variant = self._variant
        if variant == "success":
            return p.success_soft, p.success
        if variant == "warning":
            return p.warning_soft, p.warning
        if variant == "danger":
            return p.danger_soft, p.danger
        if variant == "info":
            return p.info_soft, p.info
        if variant == "secondary":
            return p.hover, p.text_secondary
        if variant == "outline":
            return "transparent", p.text_secondary
        return p.accent_soft, p.accent

    def _apply_colors(self) -> None:
        _, fg = self._colors()
        try:
            if self._label:
                self._label.setStyleSheet(f"color: {fg}; background: transparent; border: none;")
            if self._icon:
                self._icon.set_color(fg)
        except RuntimeError:
            pass  # widget being destroyed during teardown

    def paintEvent(self, event) -> None:
        bg, _ = self._colors()
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        path = QPainterPath()
        path.addRoundedRect(0.5, 0.5, self.width() - 1, self.height() - 1, 999, 999)
        painter.fillPath(path, QColor(bg))
        if str(self._variant) == "outline":
            painter.setPen(QPen(QColor(active_theme().palette.border), 1))
            painter.drawPath(path)
        painter.end()
