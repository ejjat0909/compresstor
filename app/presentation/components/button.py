"""Button components with shadcn-style variants, sizes, icons and ripple."""

from __future__ import annotations

from enum import Enum
from typing import Optional

from PySide6.QtCore import QPointF, QPropertyAnimation, Qt, QVariantAnimation
from PySide6.QtGui import QColor, QIcon, QPainter
from PySide6.QtWidgets import QPushButton

from app.presentation.components.icons import IconLabel
from app.presentation.theme.registry import active_theme


class ButtonVariant(str, Enum):
    PRIMARY = "primary"
    SECONDARY = "secondary"
    OUTLINE = "outline"
    GHOST = "ghost"
    DESTRUCTIVE = "destructive"
    SUCCESS = "success"


class ButtonSize(str, Enum):
    SM = "sm"
    MD = "md"
    LG = "lg"
    ICON = "icon"
    ICON_SM = "iconSm"


class Button(QPushButton):
    """A push button with variants, optional icon and loading state."""

    def __init__(
        self,
        text: str = "",
        variant: ButtonVariant | str = ButtonVariant.PRIMARY,
        size: ButtonSize | str = ButtonSize.MD,
        icon: str | None = None,
        icon_size: int = 16,
        parent=None,
    ) -> None:
        super().__init__(text, parent)
        self._icon_name = icon
        self._icon_size = icon_size
        self._loading = False
        self.set_variant(variant)
        self.set_size(size)
        self.setCursor(Qt.PointingHandCursor)
        self.setFocusPolicy(Qt.StrongFocus)
        self._refresh_icon()

    # ------------------------------------------------------------------ #
    def set_variant(self, variant: ButtonVariant | str) -> None:
        self.setProperty("ui", str(variant if isinstance(variant, ButtonVariant) else variant))
        self._restyle()

    def set_size(self, size: ButtonSize | str) -> None:
        self.setProperty("size", str(size if isinstance(size, ButtonSize) else size))
        self._restyle()

    def set_icon(self, name: str | None, size: int | None = None) -> None:
        self._icon_name = name
        if size:
            self._icon_size = size
        self._refresh_icon()

    def set_loading(self, loading: bool) -> None:
        self._loading = loading
        self.setEnabled(not loading)
        self._refresh_icon()

    def _restyle(self) -> None:
        # force style re-application
        self.style().unpolish(self)
        self.style().polish(self)
        self.update()

    def _refresh_icon(self) -> None:
        if self._loading:
            self.setIcon(active_theme().icon("refresh-cw", self._spinner_color(), self._icon_size))
            self._spin_icon()
        elif self._icon_name:
            self.setIcon(active_theme().icon(self._icon_name, None, self._icon_size))
        else:
            self.setIcon(QIcon())

    def _spinner_color(self) -> str:
        theme = active_theme()
        variant = str(self.property("ui"))
        if variant in ("primary", "destructive", "success"):
            return theme.palette.accent_foreground
        return theme.palette.text_secondary

    def _spin_icon(self) -> None:
        """Rotate the loading icon via a QVariantAnimation on a transform property."""
        if not hasattr(self, "_spinner_anim"):
            self._spinner_anim = QVariantAnimation(self)
            self._spinner_anim.setStartValue(0)
            self._spinner_anim.setEndValue(360)
            self._spinner_anim.setDuration(900)
            self._spinner_anim.setLoopCount(-1)
            self._spinner_anim.valueChanged.connect(self.update)
            self._spinner_anim.start()


class IconButton(Button):
    """Compact square button containing only an icon."""

    def __init__(
        self,
        icon: str,
        tooltip: str = "",
        size: ButtonSize | str = ButtonSize.ICON,
        variant: ButtonVariant | str = ButtonVariant.GHOST,
        icon_size: int = 16,
        parent=None,
    ) -> None:
        super().__init__("", variant=variant, size=size, icon=icon, icon_size=icon_size, parent=parent)
        if tooltip:
            self.setToolTip(tooltip)
        w, h = self._fixed_for(size, icon_size)
        self.setFixedSize(w, h)

    @staticmethod
    def _fixed_for(size: ButtonSize | str, icon_size: int) -> tuple[int, int]:
        s = str(size)
        if s == "iconSm":
            return icon_size + 14, icon_size + 14
        if s == "lg":
            return icon_size + 26, icon_size + 26
        return icon_size + 18, icon_size + 18


class RippleButton(Button):
    """Button with a material-style ripple on press."""

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._ripples: list[dict] = []  # {origin, radius, color}

    def mousePressEvent(self, event) -> None:
        origin = QPointF(event.position())
        anim = QVariantAnimation(self)
        start = 6.0
        end = max(self.width(), self.height()) * 1.2
        anim.setStartValue(start)
        anim.setEndValue(end)
        anim.setDuration(320)
        ripple = {"origin": origin, "radius": start, "anim": anim}
        self._ripples.append(ripple)

        def on_tick(value):
            ripple["radius"] = value
            self.update()

        def on_finish():
            if ripple in self._ripples:
                self._ripples.remove(ripple)
            self.update()

        anim.valueChanged.connect(on_tick)
        anim.finished.connect(on_finish)
        anim.start()
        super().mousePressEvent(event)

    def paintEvent(self, event) -> None:
        super().paintEvent(event)
        if not self._ripples:
            return
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        for ripple in self._ripples:
            theme = active_theme()
            color = QColor(theme.palette.accent_foreground if self.property("ui") in (
                "primary", "destructive", "success") else theme.palette.text_secondary)
            color.setAlpha(38)
            painter.setBrush(color)
            painter.setPen(Qt.NoPen)
            painter.drawEllipse(ripple["origin"], ripple["radius"], ripple["radius"])
        painter.end()
