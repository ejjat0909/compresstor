"""Tooltip helper: unified way to attach styled tooltips."""

from __future__ import annotations

from PySide6.QtWidgets import QWidget


def attach_tooltip(widget: QWidget, text: str, delay_ms: int = 350) -> None:
    """Attach a themed tooltip (styling comes from the global QToolTip QSS)."""
    widget.setToolTip(text)
    widget.setToolTipDuration(delay_ms)
