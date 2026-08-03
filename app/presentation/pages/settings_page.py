"""Settings page: theme, accent color, and compression defaults."""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QColorDialog,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QScrollArea,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from app.core.entities import AppSettings, CompressionLevel, OutputMode
from app.presentation.app_controller import AppController
from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.card import Card
from app.presentation.components.dropdown import Dropdown, FieldLabel
from app.presentation.components.inputs import Input
from app.presentation.components.switch import Switch
from app.presentation.components.typography import CaptionText, SecondaryText, SectionTitle
from app.presentation.theme.registry import active_theme

ACCENT_PRESETS = [
    ("Blue", "#2563eb"),
    ("Indigo", "#4f46e5"),
    ("Violet", "#7c3aed"),
    ("Emerald", "#059669"),
    ("Rose", "#e11d48"),
    ("Amber", "#d97706"),
    ("Sky", "#0284c7"),
    ("Slate", "#475569"),
]


class AccentSwatch(QFrame):
    """A clickable color dot."""

    selected = Signal(str)

    def __init__(self, color: str, selected: bool = False, parent=None) -> None:
        super().__init__(parent)
        self.color = color
        self._selected = selected
        self.setFixedSize(30, 30)
        self.setCursor(Qt.PointingHandCursor)
        self.setToolTip(color)
        active_theme().changed.connect(lambda _m: self.update())

    def set_selected(self, selected: bool) -> None:
        self._selected = selected
        self.update()

    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.LeftButton:
            self.selected.emit(self.color)
        super().mousePressEvent(event)

    def paintEvent(self, event) -> None:
        from PySide6.QtGui import QPainter, QPen

        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setBrush(QColor(self.color))
        pen = QPen(QColor(active_theme().palette.accent if self._selected else active_theme().palette.border), 2)
        painter.setPen(pen)
        painter.drawEllipse(3, 3, self.width() - 6, self.height() - 6)
        painter.end()


class SettingsPage(QWidget):
    def __init__(self, controller: AppController, parent=None) -> None:
        super().__init__(parent)
        self.controller = controller
        self._swatches: list[AccentSwatch] = []
        self._build()
        self._load(controller.settings)

    # ------------------------------------------------------------------ #
    def _build(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        outer.addWidget(scroll)

        container = QWidget()
        container.setObjectName("pageRoot")
        layout = QVBoxLayout(container)
        layout.setContentsMargins(28, 22, 28, 28)
        layout.setSpacing(16)
        layout.setAlignment(Qt.AlignTop)

        layout.addWidget(SectionTitle("Settings"))
        layout.addWidget(SecondaryText("Personalize Compresstor and set your default compression behaviour."))

        # ---------------- appearance card ----------------
        appearance = Card("Appearance")
        ap = appearance.body()

        ap.addWidget(CaptionText("ACCENT COLOR"))
        swatch_row = QHBoxLayout()
        swatch_row.setSpacing(8)
        for name, color in ACCENT_PRESETS:
            swatch = AccentSwatch(color)
            swatch.selected.connect(self._on_accent_selected)
            swatch_row.addWidget(swatch)
            self._swatches.append(swatch)
        self._custom_btn = Button("Custom…", ButtonVariant.OUTLINE, ButtonSize.SM, icon="palette", icon_size=13)
        self._custom_btn.clicked.connect(self._on_custom_color)
        swatch_row.addWidget(self._custom_btn)
        swatch_row.addStretch(1)
        ap.addLayout(swatch_row)

        layout.addWidget(appearance)

        # ---------------- compression defaults card ----------------
        defaults = Card("Compression Defaults")
        dp = defaults.body()

        dp.addWidget(CaptionText("DEFAULT LEVEL"))
        self._level_dropdown = Dropdown()
        self._level_dropdown.add_options([
            (CompressionLevel.HIGH.value, "High — best quality"),
            (CompressionLevel.BALANCED.value, "Balanced — recommended"),
            (CompressionLevel.MAXIMUM.value, "Maximum — smallest size"),
        ])
        dp.addWidget(self._level_dropdown)

        dp.addSpacing(6)
        dp.addWidget(CaptionText("OUTPUT"))
        self._mode_dropdown = Dropdown()
        self._mode_dropdown.add_options([
            (OutputMode.SAME_DIR_SUFFIX.value, "Next to original — new file"),
            (OutputMode.OUTPUT_DIR.value, "Into a chosen folder"),
            (OutputMode.OVERWRITE.value, "Replace original file"),
        ])
        dp.addWidget(self._mode_dropdown)

        folder_row = QHBoxLayout()
        folder_row.setSpacing(8)
        self._folder_input = Input("Default output folder…")
        self._folder_input.setReadOnly(True)
        browse = Button("Browse…", ButtonVariant.SECONDARY, ButtonSize.SM, icon="folder", icon_size=13)
        browse.clicked.connect(self._pick_folder)
        folder_row.addWidget(self._folder_input, 1)
        folder_row.addWidget(browse)
        dp.addLayout(folder_row)

        suffix_row = QHBoxLayout()
        suffix_row.setSpacing(8)
        self._suffix_input = Input("suffix")
        self._suffix_input.setText("_compressed")
        suffix_row.addWidget(FieldLabel("Suffix", self._suffix_input))
        dp.addLayout(suffix_row)

        dp.addSpacing(6)
        dp.addWidget(CaptionText("BEHAVIOUR"))
        self._history_switch = Switch(True)
        dp.addWidget(FieldLabel("Add results to history", self._history_switch))
        self._confirm_switch = Switch(True)
        dp.addWidget(FieldLabel("Confirm before overwriting", self._confirm_switch))
        history_row = QHBoxLayout()
        history_row.setSpacing(8)
        self._history_limit = QSpinBox()
        self._history_limit.setRange(25, 2000)
        self._history_limit.setSingleStep(25)
        self._history_limit.setValue(200)
        history_row.addWidget(FieldLabel("History limit", self._history_limit))
        dp.addLayout(history_row)

        layout.addWidget(defaults)

        # ---------------- about card ----------------
        about = Card("About")
        ab = about.body()
        ab.addWidget(SecondaryText("Compresstor 1.0.0"))
        ab.addWidget(CaptionText(
            "Compresses PDF and image files entirely on your device. "
            "Files never leave your computer."
        ))
        layout.addWidget(about)

        # ---------------- actions ----------------
        actions = QHBoxLayout()
        actions.setSpacing(8)
        actions.addStretch(1)
        self._reset_btn = Button("Reset to defaults", ButtonVariant.GHOST, ButtonSize.MD, icon="rotate-ccw", icon_size=14)
        self._reset_btn.clicked.connect(self._on_reset)
        actions.addWidget(self._reset_btn)
        self._save_btn = Button("Save settings", ButtonVariant.PRIMARY, ButtonSize.MD, icon="save", icon_size=14)
        self._save_btn.clicked.connect(self._on_save)
        actions.addWidget(self._save_btn)
        layout.addLayout(actions)

        layout.addStretch(1)
        scroll.setWidget(container)

    # ------------------------------------------------------------------ #
    def _load(self, s: AppSettings) -> None:
        self._level_dropdown.set_value(s.default_level)
        self._mode_dropdown.set_value(s.output_mode)
        self._folder_input.setText(s.output_dir)
        self._suffix_input.setText("_compressed")
        self._history_switch.setChecked(s.add_to_history)
        self._confirm_switch.setChecked(s.overwrite_confirmation)
        self._history_limit.setValue(s.history_limit)
        self._mark_accent(s.accent_color)

    def _mark_accent(self, color: str) -> None:
        normalized = color.lower()
        for swatch in self._swatches:
            swatch.set_selected(swatch.color.lower() == normalized)
        self._current_accent = color

    # ------------------------------------------------------------------ #
    def _on_accent_selected(self, color: str) -> None:
        self._mark_accent(color)
        active_theme().configure(accent=color)

    def _on_custom_color(self) -> None:
        color = QColorDialog.getColor(QColor(self._current_accent), self, "Choose accent color")
        if color.isValid():
            hex_color = color.name()
            self._mark_accent(hex_color)
            active_theme().configure(accent=hex_color)

    def _pick_folder(self) -> None:
        folder = QFileDialog.getExistingDirectory(self, "Choose default output folder")
        if folder:
            self._folder_input.setText(folder)

    # ------------------------------------------------------------------ #
    def _collect(self) -> AppSettings:
        s = self.controller.settings
        s.accent_color = getattr(self, "_current_accent", "#3b82f6")
        s.default_level = self._level_dropdown.current_value() or CompressionLevel.BALANCED.value
        s.output_mode = self._mode_dropdown.current_value() or OutputMode.SAME_DIR_SUFFIX.value
        s.output_dir = self._folder_input.text()
        s.add_to_history = self._history_switch.isChecked()
        s.overwrite_confirmation = self._confirm_switch.isChecked()
        s.history_limit = self._history_limit.value()
        return s

    def _on_save(self) -> None:
        self.controller.save_settings(self._collect())
        window = self.window()
        if hasattr(window, "toasts"):
            window.toasts.success("Settings saved", "Your preferences have been updated.")

    def _on_reset(self) -> None:
        fresh = AppSettings()
        self.controller.save_settings(fresh)
        active_theme().configure(accent=fresh.accent_color)
        self._load(fresh)
        window = self.window()
        if hasattr(window, "toasts"):
            window.toasts.info("Settings reset", "All settings restored to defaults.")
