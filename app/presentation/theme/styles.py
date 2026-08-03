"""Theme manager: palette selection, QSS generation, and application-wide theming.

The theme engine renders a complete stylesheet from palette tokens so the
entire app (including custom-painted widgets) follows one source of truth.
"""

from __future__ import annotations

import logging
import os
from dataclasses import replace
from pathlib import Path

from PySide6.QtCore import QObject, Qt, Signal
from PySide6.QtGui import QColor, QIcon, QPixmap
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtWidgets import QApplication

from app.presentation.theme.palette import DARK, LIGHT, Palette, hex_to_rgba
from app.resources import resource_path

log = logging.getLogger(__name__)

ASSET_DIR = resource_path("assets")

MODE_LIGHT = "light"
MODE_DARK = "dark"


class ThemeManager(QObject):
    """Owns the current palette and applies QSS to the application."""

    changed = Signal(str)  # emits the new mode ("light" | "dark")

    def __init__(self, app: QApplication) -> None:
        super().__init__()
        self._app = app
        self._mode = MODE_LIGHT
        self._accent = "#2563eb"
        self._palette: Palette = LIGHT
        self._icon_cache: dict[tuple[str, str, int], QIcon] = {}
        self._font_family = "Inter"

    # ------------------------------------------------------------------ #
    @property
    def mode(self) -> str:
        return self._mode

    @property
    def accent(self) -> str:
        return self._accent

    @property
    def palette(self) -> Palette:
        return self._palette

    @property
    def is_dark(self) -> bool:
        return self._mode == MODE_DARK

    # ------------------------------------------------------------------ #
    def set_font_family(self, family: str) -> None:
        self._font_family = family

    def configure(self, mode: str | None = None, accent: str | None = None) -> None:
        if mode in (MODE_LIGHT, MODE_DARK):
            self._mode = mode
        if accent and QColor(accent).isValid():
            self._accent = accent
        self._rebuild()

    def detect_system_mode(self) -> str:
        """Resolve the OS color scheme via Qt style hints."""
        try:
            scheme = self._app.styleHints().colorScheme()
            return MODE_DARK if scheme == Qt.ColorScheme.Dark else MODE_LIGHT
        except Exception:
            return MODE_LIGHT

    def _rebuild(self) -> None:
        base = DARK if self._mode == MODE_DARK else LIGHT
        self._palette = replace(base, accent=self._accent)
        self._icon_cache.clear()
        self._app.setStyle("Fusion")
        self._app.setStyleSheet(build_stylesheet(self._palette, self._font_family))
        self.changed.emit(self._mode)

    # ------------------------------------------------------------------ #
    def icon(self, name: str, color: str | None = None, size: int = 16) -> QIcon:
        """Load a lucide icon, tinted with the given color (default: current text)."""
        if color is None:
            color = self._palette.text_secondary
        key = (name, color.lower(), size)
        if key in self._icon_cache:
            return self._icon_cache[key]
        pix = self.pixmap(name, color, size)
        icon = QIcon(pix)
        self._icon_cache[key] = icon
        return icon

    def pixmap(self, name: str, color: str | None = None, size: int = 16) -> QPixmap:
        if color is None:
            color = self._palette.text_secondary
        svg_path = ASSET_DIR / "icons" / f"{name}.svg"
        if not svg_path.exists():
            return QPixmap(size, size)
        renderer = QSvgRenderer(str(svg_path))
        pix = QPixmap(size, size)
        pix.fill(Qt.transparent)
        from PySide6.QtGui import QPainter

        painter = QPainter(pix)
        try:
            renderer.render(painter)
        finally:
            painter.end()
        return _tint(pix, QColor(color))


def _tint(pixmap: QPixmap, color: QColor) -> QPixmap:
    """Recolor an outline icon by compositing it over a solid color mask."""
    from PySide6.QtGui import QPainter

    tinted = QPixmap(pixmap.size())
    tinted.fill(Qt.transparent)
    painter = QPainter(tinted)
    painter.setCompositionMode(QPainter.CompositionMode_Source)
    painter.fillRect(tinted.rect(), color)
    painter.setCompositionMode(QPainter.CompositionMode_DestinationIn)
    painter.drawPixmap(0, 0, pixmap)
    painter.end()
    return tinted


# --------------------------------------------------------------------- #
# QSS generation
# --------------------------------------------------------------------- #
def _image_cache_dir() -> Path:
    env = os.environ.get("COMPRESSTOR_DATA_DIR")
    base = Path(env) if env else None
    if base is None:
        if os.name == "nt":
            base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        else:
            base = Path.home() / "Library" / "Application Support"
    cache = base / "Compresstor" / ".theme-cache"
    cache.mkdir(parents=True, exist_ok=True)
    return cache


def _indicator_png(p: Palette, kind: str) -> str:
    """Render tiny indicator images (chevron, check, radio dot) for QSS."""
    cache = _image_cache_dir()
    key = f"{kind}_{p.accent.lstrip('#')}_{p.accent_foreground.lstrip('#')}.png"
    path = cache / key
    if path.exists():
        return str(path)
    size = {"chevron": 12, "check": 10, "radio": 8}[kind]
    pix = QPixmap(size, size)
    pix.fill(Qt.transparent)
    from PySide6.QtGui import QColor, QPainter, QPen, QPolygonF, QBrush
    from PySide6.QtCore import QPointF

    painter = QPainter(pix)
    painter.setRenderHint(QPainter.Antialiasing)
    if kind == "chevron":
        pen = QPen(QColor(p.text_muted), 1.6)
        painter.setPen(pen)
        painter.drawPolyline(
            QPolygonF([QPointF(2, 4), QPointF(6, 8), QPointF(10, 4)])
        )
    elif kind == "check":
        pen = QPen(QColor(p.accent_foreground), 2.0, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
        painter.setPen(pen)
        painter.drawPolyline(
            QPolygonF([QPointF(1.5, 5.5), QPointF(4, 8), QPointF(8.5, 2.5)])
        )
    elif kind == "radio":
        painter.setBrush(QBrush(QColor(p.accent)))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(QPointF(size / 2, size / 2), 2.4, 2.4)
    painter.end()
    pix.toImage().save(str(path), "PNG")
    return str(path)


def build_stylesheet(p: Palette, font_family: str) -> str:
    """Generate the complete application stylesheet from palette tokens."""
    chevron = _indicator_png(p, "chevron")
    check = _indicator_png(p, "check")
    radio = _indicator_png(p, "radio")
    accent = p.accent
    danger = p.danger

    return f"""
/* ============================= base ============================= */
QWidget {{
    background-color: {p.bg};
    color: {p.text};
    font-family: "{font_family}";
    font-size: 13pt;
    selection-background-color: {p.selection};
    selection-color: {p.text};
}}
QMainWindow, QDialog {{ background-color: {p.bg}; }}
QWidget#appRoot {{ background-color: {p.bg}; }}
QFrame#pageRoot {{ background-color: transparent; }}

/* sidebar + header surfaces */
QFrame#sidebar {{
    background-color: {p.sidebar};
    border-right: 1px solid {p.border};
}}
QFrame#appHeader {{
    background-color: {p.header};
    border-bottom: 1px solid {p.border_soft};
}}

/* ========================= typography =========================== */
QLabel[ui="pageTitle"] {{ font-size: 20pt; font-weight: 700; color: {p.text}; background: transparent; }}
QLabel[ui="sectionTitle"] {{ font-size: 15pt; font-weight: 600; color: {p.text}; background: transparent; }}
QLabel[ui="cardTitle"] {{ font-size: 13.5pt; font-weight: 600; color: {p.text}; background: transparent; }}
QLabel[ui="normal"] {{ font-size: 13pt; color: {p.text}; background: transparent; }}
QLabel[ui="secondary"] {{ font-size: 12.5pt; color: {p.text_secondary}; background: transparent; }}
QLabel[ui="caption"] {{ font-size: 11pt; color: {p.text_muted}; background: transparent; }}
QLabel[ui="muted"] {{ font-size: 12.5pt; color: {p.text_muted}; background: transparent; }}

/* ============================ cards ============================= */
QFrame[ui="card"] {{
    background-color: {p.card};
    border: 1px solid {p.border};
    border-radius: 12px;
}}
QFrame[ui="card"][hover="true"] {{
    background-color: {p.card_hover};
    border-color: {p.border_strong};
}}
QFrame[ui="cardSubtle"] {{
    background-color: {p.card_hover};
    border: 1px solid {p.border_soft};
    border-radius: 10px;
}}

/* =========================== buttons ============================ */
QPushButton {{
    border: none;
    border-radius: 8px;
    padding: 7px 16px;
    font-weight: 500;
    font-size: 12.5pt;
    background-color: {p.hover};
    color: {p.text};
    outline: none;
}}
QPushButton:hover {{ background-color: {p.active}; }}
QPushButton:pressed {{ background-color: {hex_to_rgba(p.accent, 0.14)}; }}
QPushButton:disabled {{ color: {p.text_muted}; background-color: transparent; }}

QPushButton[ui="primary"] {{
    background-color: {accent};
    color: {p.accent_foreground};
    font-weight: 600;
}}
QPushButton[ui="primary"]:hover {{ background-color: {p.accent_hover}; }}
QPushButton[ui="primary"]:pressed {{ background-color: {p.accent_active}; }}
QPushButton[ui="primary"]:disabled {{ background-color: {hex_to_rgba(accent, 0.35)}; color: {hex_to_rgba(p.accent_foreground, 0.7)}; }}
QPushButton[ui="primary"]:focus {{ border: 2px solid {hex_to_rgba(p.accent, 0.55)}; }}

QPushButton[ui="secondary"] {{ background-color: {p.card}; border: 1px solid {p.border}; color: {p.text}; }}
QPushButton[ui="secondary"]:hover {{ background-color: {p.card_hover}; border-color: {p.border_strong}; }}
QPushButton[ui="secondary"]:pressed {{ background-color: {p.hover}; }}
QPushButton[ui="secondary"]:disabled {{ color: {p.text_muted}; border-color: {p.border_soft}; background-color: {p.bg}; }}

QPushButton[ui="outline"] {{ background-color: transparent; border: 1px solid {p.border}; color: {p.text}; }}
QPushButton[ui="outline"]:hover {{ background-color: {p.hover}; border-color: {p.border_strong}; }}
QPushButton[ui="outline"]:pressed {{ background-color: {p.active}; }}

QPushButton[ui="ghost"] {{ background-color: transparent; color: {p.text_secondary}; }}
QPushButton[ui="ghost"]:hover {{ background-color: {p.hover}; color: {p.text}; }}
QPushButton[ui="ghost"]:pressed {{ background-color: {p.active}; }}

QPushButton[ui="destructive"] {{ background-color: {danger}; color: #ffffff; font-weight: 600; }}
QPushButton[ui="destructive"]:hover {{ background-color: {p.danger_hover}; }}
QPushButton[ui="destructive"]:pressed {{ background-color: {p.danger_hover}; }}
QPushButton[ui="destructive"]:disabled {{ background-color: {hex_to_rgba(danger, 0.35)}; }}

QPushButton[ui="success"] {{ background-color: {p.success}; color: #ffffff; font-weight: 600; }}
QPushButton[ui="success"]:hover {{ background-color: {p.success}; }}
QPushButton[ui="success"]:disabled {{ background-color: {hex_to_rgba(p.success, 0.35)}; }}

/* sizes */
QPushButton[size="sm"] {{ padding: 4px 10px; font-size: 11.5pt; border-radius: 6px; }}
QPushButton[size="lg"] {{ padding: 10px 22px; font-size: 13pt; border-radius: 10px; }}
QPushButton[size="icon"] {{ padding: 6px; border-radius: 8px; }}
QPushButton[size="iconSm"] {{ padding: 4px; border-radius: 6px; }}

/* ============================ inputs ============================ */
QLineEdit, QTextEdit, QPlainTextEdit, QSpinBox {{
    background-color: {p.input};
    border: 1px solid {p.border};
    border-radius: 8px;
    padding: 7px 12px;
    font-size: 12.5pt;
    color: {p.text};
    selection-background-color: {p.accent_soft};
}}
QLineEdit:hover, QTextEdit:hover, QPlainTextEdit:hover, QSpinBox:hover {{ border-color: {p.border_strong}; }}
QLineEdit:focus, QTextEdit:focus, QPlainTextEdit:focus, QSpinBox:focus {{
    border-color: {accent};
    background-color: {p.input};
}}
QLineEdit:disabled, QTextEdit:disabled {{ color: {p.text_muted}; background-color: {p.bg}; }}
QLineEdit::placeholder {{ color: {p.text_muted}; }}

/* ============================ search ============================ */
QLineEdit[ui="search"] {{
    border-radius: 10px;
    padding: 7px 12px 7px 34px;
    background-color: {p.input};
    border: 1px solid {p.border};
    font-size: 12.5pt;
}}
QLineEdit[ui="search"]:focus {{ border-color: {accent}; }}

/* ========================== combo box =========================== */
QComboBox {{
    background-color: {p.input};
    border: 1px solid {p.border};
    border-radius: 8px;
    padding: 6px 32px 6px 12px;
    font-size: 12.5pt;
    color: {p.text};
}}
QComboBox:hover {{ border-color: {p.border_strong}; }}
QComboBox:focus {{ border-color: {accent}; }}
QComboBox:disabled {{ color: {p.text_muted}; background-color: {p.bg}; }}
QComboBox::drop-down {{ border: none; width: 28px; }}
QComboBox::down-arrow {{ image: url("{chevron}"); width: 12px; height: 12px; }}
QComboBox QAbstractItemView {{
    background-color: {p.card};
    border: 1px solid {p.border};
    border-radius: 10px;
    padding: 4px;
    selection-background-color: {p.accent_soft};
    selection-color: {p.text};
    outline: none;
}}
QComboBox QAbstractItemView::item {{ padding: 6px 10px; border-radius: 6px; min-height: 20px; }}
QComboBox QAbstractItemView::item:hover {{ background-color: {p.hover}; }}

/* ===================== checkboxes & radios ====================== */
QCheckBox, QRadioButton {{
    spacing: 8px;
    font-size: 12.5pt;
    color: {p.text};
    background: transparent;
}}
QCheckBox::indicator, QRadioButton::indicator {{
    width: 18px; height: 18px;
    border: 1.5px solid {p.border_strong};
    border-radius: 6px;
    background-color: {p.input};
}}
QCheckBox::indicator:hover {{ border-color: {accent}; }}
QCheckBox::indicator:checked {{
    background-color: {accent};
    border-color: {accent};
    image: url("{check}");
}}
QCheckBox::indicator:disabled {{ border-color: {p.border}; background-color: {p.bg}; }}
QRadioButton::indicator {{ border-radius: 9px; }}
QRadioButton::indicator:checked {{
    border: 1.5px solid {accent};
    background-color: {p.input};
    image: url("{radio}");
}}
QRadioButton::indicator:hover {{ border-color: {accent}; }}

/* ========================== progress ============================ */
QProgressBar {{
    background-color: {p.hover};
    border: none;
    border-radius: 4px;
    height: 8px;
    text-align: center;
}}
QProgressBar::chunk {{
    background-color: {accent};
    border-radius: 4px;
}}
QProgressBar[ui="success"]::chunk {{ background-color: {p.success}; }}
QProgressBar[ui="danger"]::chunk {{ background-color: {p.danger}; }}

/* ============================ tables ============================ */
QTableWidget {{
    background-color: transparent;
    border: none;
    gridline-color: transparent;
    outline: none;
    font-size: 12.5pt;
    alternate-background-color: transparent;
}}
QTableWidget::item {{
    padding: 4px 8px;
    border: none;
    border-bottom: 1px solid {p.border_soft};
    color: {p.text};
}}
QTableWidget::item:selected {{ background-color: {p.accent_soft}; color: {p.text}; }}
QTableWidget::item:hover {{ background-color: {p.hover}; }}
QHeaderView::section {{
    background-color: transparent;
    color: {p.text_muted};
    font-size: 11pt;
    font-weight: 600;
    padding: 8px 10px;
    border: none;
    border-bottom: 1px solid {p.border};
    text-align: left;
}}
QTableCornerButton::section {{ background: transparent; border: none; }}

/* ============================ menus ============================= */
QMenu {{
    background-color: {p.card};
    border: 1px solid {p.border};
    border-radius: 10px;
    padding: 5px;
}}
QMenu::item {{
    padding: 7px 28px 7px 12px;
    border-radius: 6px;
    font-size: 12.5pt;
    color: {p.text};
}}
QMenu::item:selected {{ background-color: {p.accent_soft}; color: {p.text}; }}
QMenu::item:disabled {{ color: {p.text_muted}; }}
QMenu::separator {{ height: 1px; background-color: {p.border_soft}; margin: 5px 8px; }}
QMenu::icon {{ padding-left: 8px; }}

/* ========================== tooltips ============================ */
QToolTip {{
    background-color: {p.text};
    color: {p.bg};
    border: none;
    border-radius: 6px;
    padding: 5px 9px;
    font-size: 11pt;
}}

/* ========================= scrollbars =========================== */
QScrollBar:vertical {{
    background: transparent; width: 10px; margin: 2px;
}}
QScrollBar::handle:vertical {{
    background-color: {p.scrollbar};
    border-radius: 4px; min-height: 32px;
}}
QScrollBar::handle:vertical:hover {{ background-color: {p.scrollbar_hover}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {{ background: transparent; }}
QScrollBar:horizontal {{
    background: transparent; height: 10px; margin: 2px;
}}
QScrollBar::handle:horizontal {{
    background-color: {p.scrollbar};
    border-radius: 4px; min-width: 32px;
}}
QScrollBar::handle:horizontal:hover {{ background-color: {p.scrollbar_hover}; }}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{ width: 0; }}
QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal {{ background: transparent; }}

/* ============================= tabs ============================= */
QTabWidget::pane {{ border: none; background: transparent; }}
QTabBar::tab {{
    background: transparent;
    color: {p.text_muted};
    padding: 7px 14px;
    margin-right: 4px;
    border: none;
    border-radius: 8px;
    font-size: 12.5pt;
    font-weight: 500;
}}
QTabBar::tab:hover {{ color: {p.text}; background-color: {p.hover}; }}
QTabBar::tab:selected {{ color: {p.text}; background-color: {p.accent_soft}; }}

/* ======================= list & list items ====================== */
QListWidget {{
    background-color: transparent;
    border: none;
    outline: none;
}}
QListWidget::item {{ padding: 6px 10px; border-radius: 8px; }}
QListWidget::item:hover {{ background-color: {p.hover}; }}
QListWidget::item:selected {{ background-color: {p.accent_soft}; color: {p.text}; }}

/* ========================== splitters =========================== */
QSplitter::handle {{ background-color: {p.border_soft}; }}
QSplitter::handle:horizontal {{ width: 1px; }}
QSplitter::handle:vertical {{ height: 1px; }}

/* ======================== status bar ============================ */
QStatusBar {{ background: transparent; color: {p.text_muted}; }}
QStatusBar::item {{ border: none; }}

/* ========================= scroll area ========================== */
QScrollArea {{ background: transparent; border: none; }}
QScrollArea > QWidget > QWidget {{ background: transparent; }}
"""
