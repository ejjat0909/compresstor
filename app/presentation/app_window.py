"""Main application window: sidebar + header + page stack."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from app.presentation.app_controller import AppController
from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.toast import ToastManager
from app.presentation.components.tooltip import attach_tooltip
from app.presentation.theme.registry import active_theme
from app.presentation.widgets.sidebar import Sidebar


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
        # dark-only: apply the persisted accent color
        theme.configure(accent=controller.settings.accent_color)

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
    def _show_about(self) -> None:
        self.toasts.info(
            "Compresstor 1.0.0",
            "Compress PDF and image files locally — your files never leave this device.",
        )

    def closeEvent(self, event) -> None:
        self.controller.shutdown()
        super().closeEvent(event)
