"""Input components: text input and search bar."""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLineEdit

from app.presentation.components.icons import IconLabel


class Input(QLineEdit):
    def __init__(self, placeholder: str = "", text: str = "", parent=None) -> None:
        super().__init__(text, parent)
        self.setPlaceholderText(placeholder)
        self.setClearButtonEnabled(True)


class SearchBar(QFrame):
    """A search input with a magnifier icon (shadcn-style)."""

    textChanged = Signal(str)
    submitted = Signal(str)

    def __init__(self, placeholder: str = "Search…", parent=None) -> None:
        super().__init__(parent)
        self.setProperty("ui", "cardSubtle")
        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 4, 8, 4)
        layout.setSpacing(8)

        self._icon = IconLabel("search", 15)
        layout.addWidget(self._icon)

        self._edit = QLineEdit()
        self._edit.setProperty("ui", "search")
        self._edit.setPlaceholderText(placeholder)
        self._edit.setFrame(False)
        self._edit.textChanged.connect(self.textChanged)
        self._edit.returnPressed.connect(lambda: self.submitted.emit(self._edit.text()))
        layout.addWidget(self._edit, 1)

    def text(self) -> str:
        return self._edit.text()

    def set_text(self, value: str) -> None:
        self._edit.setText(value)

    def focus(self) -> None:
        self._edit.setFocus()
