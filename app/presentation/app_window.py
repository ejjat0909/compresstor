"""Main application window: sidebar + header + page stack."""

from __future__ import annotations

from PySide6.QtCore import QEasingCurve, QPropertyAnimation, Qt, Signal
from PySide6.QtWidgets import (
    QFrame,
    QGraphicsOpacityEffect,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from app.presentation.app_controller import AppController
from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.icons import IconLabel
from app.presentation.components.toast import ToastManager
from app.presentation.components.tooltip import attach_tooltip
from app.presentation.theme.registry import active_theme
from app.presentation.widgets.sidebar import Sidebar


class ThemeSegmented(QFrame):
    """System / Light / Dark segmented control in the header."""

    selected = Signal(str)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._buttons: dict[str, Button] = {}
        layout = QHBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.setSpacing(2)
        for key, icon, tip in (
            ("system", "monitor", "Follow system theme"),
            ("light", "sun", "Light mode"),
            ("dark", "moon", "Dark mode"),
        ):
            btn = Button("", ButtonVariant.GHOST, ButtonSize.ICON_SM, icon=icon, icon_size=15)
            attach_tooltip(btn, tip)
            btn.clicked.connect(lambda _=False, k=key: self._select(k))
            layout.addWidget(btn)
            self._buttons[key] = btn
        self.setProperty("ui", "cardSubtle")

    def _select(self, key: str) -> None:
        for k, btn in self._buttons.items():
            btn.setProperty("ui", str(ButtonVariant.SECONDARY) if k == key else str(ButtonVariant.GHOST))
            btn.style().unpolish(btn)
            btn.style().polish(btn)
        self.selected.emit(key)

    def set_selected(self, key: str) -> None:
        self._select(key)


class MainWindow(QMainWindow):
    def __init__(self, controller: AppController) -> None:
        super().__init__()
        self.controller = controller
        self.setWindowTitle("Compresstor")
        self.resize(1280, 820)
        self.setMinimumSize(1040, 680)
        self._pages: dict[str, QWidget] = {}
        self._titles: dict[str, str] = {}
        self._build()
        self.toasts = ToastManager(self)

        theme = active_theme()
        # initial theme from settings
        s = controller.settings
        mode = theme.detect_system_mode() if s.theme == "system" else s.theme
        theme.configure(mode=mode, accent=s.accent_color)
        self._theme_segmented.set_selected(s.theme)

    # ------------------------------------------------------------------ #
    def _build(self) -> None:
        central = QWidget()
        central.setObjectName("appRoot")
        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        self.sidebar = Sidebar()
        self.sidebar.add_page("dashboard", "Dashboard", "gauge")
        self.sidebar.add_page("history", "History", "history")
        self.sidebar.navigation_requested.connect(self.navigate)
        root.addWidget(self.sidebar)

        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(0)
        right_layout.addWidget(self._build_header())
        self.stack = QStackedWidget()
        right_layout.addWidget(self.stack, 1)
        root.addWidget(right, 1)

        self.setCentralWidget(central)

    def _build_header(self) -> QFrame:
        header = QFrame()
        header.setObjectName("appHeader")
        header.setFixedHeight(64)
        layout = QHBoxLayout(header)
        layout.setContentsMargins(28, 10, 28, 10)
        layout.setSpacing(12)

        self._page_title = QLabel("Dashboard")
        self._page_title.setStyleSheet(
            "font-size: 16pt; font-weight: 700; background: transparent; color: palette(text);"
        )
        layout.addWidget(self._page_title)

        layout.addStretch(1)

        self._theme_segmented = ThemeSegmented()
        self._theme_segmented.selected.connect(self._on_theme_selected)
        layout.addWidget(self._theme_segmented)

        about = Button("", ButtonVariant.GHOST, ButtonSize.ICON, icon="info", icon_size=17)
        attach_tooltip(about, "About Compresstor")
        about.clicked.connect(self._show_about)
        layout.addWidget(about)
        return header

    # ------------------------------------------------------------------ #
    def register_page(self, key: str, widget: QWidget, title: str) -> None:
        self.stack.addWidget(widget)
        self._pages[key] = widget
        self._titles[key] = title

    def navigate(self, key: str) -> None:
        widget = self._pages.get(key)
        if widget is None or self.stack.currentWidget() is widget:
            return
        self.sidebar.set_current(key)
        self._page_title.setText(self._titles.get(key, key))
        # Note: no QGraphicsOpacityEffect here — rendering a page through a
        # graphics effect drops QSS backgrounds (Qt offscreen-render bug).
        self.stack.setCurrentWidget(widget)

    # ------------------------------------------------------------------ #
    def _on_theme_selected(self, key: str) -> None:
        theme = active_theme()
        mode = theme.detect_system_mode() if key == "system" else key
        theme.configure(mode=mode)
        s = self.controller.settings
        s.theme = key
        self.controller.save_settings(s)

    def _show_about(self) -> None:
        self.toasts.info(
            "Compresstor 1.0.0",
            "Compress PDF and image files locally — your files never leave this device.",
        )

    def closeEvent(self, event) -> None:
        self.controller.shutdown()
        super().closeEvent(event)
