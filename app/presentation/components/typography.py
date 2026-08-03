"""Typography helpers: styled QLabels for the type hierarchy."""

from __future__ import annotations

from PySide6.QtWidgets import QLabel


class PageTitle(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "pageTitle")


class SectionTitle(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "sectionTitle")


class CardTitle(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "cardTitle")


class NormalText(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "normal")


class SecondaryText(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "secondary")


class CaptionText(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "caption")


class MutedText(QLabel):
    def __init__(self, text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setProperty("ui", "muted")
