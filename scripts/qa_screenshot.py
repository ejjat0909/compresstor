"""Visual QA harness: boots the app offscreen, runs a real compression,
and captures PNG screenshots of every page in both themes.

Usage:  QT_QPA_PLATFORM=offscreen python scripts/qa_screenshot.py [out_dir]
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("COMPRESSTOR_DATA_DIR", "/tmp/compresstor-qa-data")

from PySide6.QtCore import QEventLoop, QTimer  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

from app.presentation.app_controller import AppController  # noqa: E402
from app.presentation.app_window import MainWindow  # noqa: E402
from app.presentation.pages.dashboard_page import DashboardPage  # noqa: E402
from app.presentation.pages.history_page import HistoryPage  # noqa: E402
from app.presentation.pages.settings_page import SettingsPage  # noqa: E402
from app.presentation.theme.fonts import load_fonts  # noqa: E402
from app.presentation.theme.registry import set_active_theme  # noqa: E402
from app.presentation.theme.styles import ThemeManager  # noqa: E402


def make_samples(tmp: Path) -> list[str]:
    from PIL import Image, ImageDraw

    import fitz

    img = Image.new("RGB", (1400, 1000), (110, 120, 135))
    d = ImageDraw.Draw(img)
    for i in range(1200):
        x, y = i * 9 % 1400, i * 13 % 1000
        d.ellipse([x, y, x + 50, y + 50], fill=(i % 255, (i * 2) % 255, (i * 4) % 255))
    photo = tmp / "vacation-photo.jpg"
    img.save(photo, "JPEG", quality=98, subsampling=0)

    logo = Image.new("RGBA", (900, 700), (220, 60, 60, 255))
    logo_path = tmp / "brand-logo.png"
    logo.save(logo_path, "PNG")

    doc = fitz.open()
    for i in range(4):
        page = doc.new_page(width=595, height=842)
        page.insert_text((72, 90), f"Compresstor sample report — page {i + 1}", fontsize=20)
        page.insert_image(fitz.Rect(72, 140, 420, 400), filename=str(photo))
        page.insert_text((72, 700), "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", fontsize=11)
    pdf = tmp / "quarterly-report.pdf"
    doc.save(pdf, garbage=0, deflate=False)
    doc.close()

    plain = tmp / "notes.txt"
    plain.write_text("not supported")

    return [str(photo), str(logo_path), str(pdf), str(plain)]


def spin_until(predicate, timeout_ms: int = 60_000) -> bool:
    loop = QEventLoop()
    state = {"left": timeout_ms}

    def check():
        if predicate() or state["left"] <= 0:
            loop.quit()
        else:
            state["left"] -= 100
            QTimer.singleShot(100, check)

    QTimer.singleShot(100, check)
    loop.exec()
    return predicate()


def main() -> int:
    from PySide6.QtTest import QTest

    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/compresstor-qa")
    out_dir.mkdir(parents=True, exist_ok=True)

    app = QApplication(sys.argv)
    theme = ThemeManager(app)
    set_active_theme(theme)
    theme.set_font_family(load_fonts())
    theme.configure(mode="light", accent="#2563eb")

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
    app.processEvents()

    tmp = Path(tempfile.mkdtemp(prefix="compresstor-qa-samples-"))
    samples = make_samples(tmp)
    dashboard._on_files_dropped(samples)
    QTest.qWait(400)

    window.grab().save(str(out_dir / "1-dashboard-light-empty.png"))

    # ---- run a real compression through the UI ----------------------- #
    print("compressing…")
    dashboard._on_compress()
    spin_until(lambda: not controller.running, timeout_ms=120_000)
    QTest.qWait(500)
    window.grab().save(str(out_dir / "2-dashboard-light-after.png"))

    # ---- history page -------------------------------------------------- #
    window.navigate("history")
    QTest.qWait(400)
    window.grab().save(str(out_dir / "3-history-light.png"))

    # ---- settings page ------------------------------------------------- #
    window.navigate("settings")
    QTest.qWait(400)
    window.grab().save(str(out_dir / "4-settings-light.png"))

    # ---- dark mode everywhere ------------------------------------------ #
    theme.configure(mode="dark", accent="#2563eb")
    QTest.qWait(400)
    window.navigate("dashboard")
    QTest.qWait(400)
    window.grab().save(str(out_dir / "5-dashboard-dark-after.png"))
    window.navigate("history")
    QTest.qWait(400)
    window.grab().save(str(out_dir / "6-history-dark.png"))
    window.navigate("settings")
    QTest.qWait(400)
    window.grab().save(str(out_dir / "7-settings-dark.png"))

    # ---- toasts visible (success toast from compression should still be there) ---
    QTest.qWait(300)
    window.grab().save(str(out_dir / "8-toasts.png"))

    print("screenshots ->", out_dir)
    controller.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
