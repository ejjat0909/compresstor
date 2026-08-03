"""Compresstor — application entry point.

Composition root: wires the core use cases, adapters and the Qt
presentation layer together, then starts the event loop.
"""

from __future__ import annotations

import logging
import sys

from PySide6.QtWidgets import QApplication

from app.presentation.app_controller import AppController
from app.presentation.app_window import MainWindow
from app.presentation.pages.dashboard_page import DashboardPage
from app.presentation.pages.history_page import HistoryPage
from app.presentation.pages.settings_page import SettingsPage
from app.presentation.theme.fonts import app_font, load_fonts
from app.presentation.theme.registry import set_active_theme
from app.presentation.theme.styles import ThemeManager

APP_NAME = "Compresstor"
APP_VERSION = "1.0.0"


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    QApplication.setApplicationName(APP_NAME)
    QApplication.setApplicationVersion(APP_VERSION)
    QApplication.setOrganizationName("Compresstor")

    app = QApplication(sys.argv)

    # ---- theme + fonts ------------------------------------------------ #
    theme = ThemeManager(app)
    set_active_theme(theme)
    family = load_fonts()
    theme.set_font_family(family)
    app.setFont(app_font())

    # ---- composition root --------------------------------------------- #
    controller = AppController()
    window = MainWindow(controller)

    dashboard = DashboardPage(controller)
    history = HistoryPage(controller)
    settings = SettingsPage(controller)

    window.register_page("dashboard", dashboard, "Dashboard")
    window.register_page("history", history, "History")
    window.register_page("settings", settings, "Settings")

    dashboard.history_changed.connect(history.refresh)
    controller.compression_finished.connect(lambda _r: history.refresh())

    window.sidebar.set_current("dashboard")
    window.show()

    exit_code = app.exec()
    controller.shutdown()
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
