"""Dashboard page: upload, queue, settings, compression progress."""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QScrollArea,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from app.core.entities import (
    CompressionLevel,
    FileItem,
    FileKind,
    JobResult,
    JobStatus,
    OutputMode,
)
from app.presentation.app_controller import AppController
from app.presentation.components.accordion import Accordion
from app.presentation.components.badge import Badge, BadgeVariant
from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.card import Card
from app.presentation.components.dropdown import Dropdown, FieldLabel
from app.presentation.components.filetable import Column, FileTable
from app.presentation.components.icons import IconLabel
from app.presentation.components.inputs import Input
from app.presentation.components.modal import confirm
from app.presentation.components.progress import ProgressBar
from app.presentation.components.switch import Switch
from app.presentation.components.tooltip import attach_tooltip
from app.presentation.components.typography import (
    CaptionText,
    MutedText,
    NormalText,
    SecondaryText,
    SectionTitle,
)
from app.presentation.components.uploadarea import UploadArea
from app.presentation.components.utils import format_size
from app.presentation.theme.registry import active_theme

LEVEL_META = {
    CompressionLevel.HIGH: ("High", "Best quality, modest savings"),
    CompressionLevel.BALANCED: ("Balanced", "Great quality, good savings"),
    CompressionLevel.MAXIMUM: ("Maximum", "Smallest size, some quality loss"),
}


class LevelPreset(QFrame):
    """Selectable preset card for compression level."""

    def __init__(self, level: CompressionLevel, parent=None) -> None:
        super().__init__(parent)
        self.level = level
        self._selected = False
        self.setCursor(Qt.PointingHandCursor)
        self.setMinimumHeight(64)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 10, 12, 10)
        layout.setSpacing(2)
        name, desc = LEVEL_META[level]
        self._name = NormalText(name)
        self._desc = CaptionText(desc)
        layout.addWidget(self._name)
        layout.addWidget(self._desc)
        active_theme().changed.connect(lambda _m: self.update())

    def set_selected(self, selected: bool) -> None:
        self._selected = selected
        self.update()

    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.LeftButton:
            self.selected.emit(self.level)
        super().mousePressEvent(event)

    selected = Signal(object)

    def paintEvent(self, event) -> None:
        from PySide6.QtGui import QColor, QPainter

        p = active_theme().palette
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        border = QColor(p.accent if self._selected else p.border)
        if self._selected:
            painter.setBrush(QColor(p.accent_soft))
        else:
            painter.setBrush(QColor(p.card))
        painter.setPen(border)
        painter.drawRoundedRect(1, 1, self.width() - 2, self.height() - 2, 10, 10)
        painter.end()
        color = p.accent if self._selected else p.text
        self._name.setStyleSheet(f"color: {color}; background: transparent; font-weight: 600;")
        self._desc.setStyleSheet("color: palette(text); background: transparent;")


class DashboardPage(QWidget):
    """The main compression work surface."""

    history_changed = Signal()

    def __init__(self, controller: AppController, parent=None) -> None:
        super().__init__(parent)
        self.controller = controller
        self._status_by_path: dict[str, JobStatus] = {}
        self._current_file: str | None = None
        self._build()
        self._refresh_queue()

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

        # ---- header row -------------------------------------------------
        header = QHBoxLayout()
        header.setSpacing(12)
        title_col = QVBoxLayout()
        title_col.setSpacing(2)
        title_col.addWidget(SectionTitle("Compress Files"))
        subtitle = SecondaryText("Reduce PDF and image file sizes — fast, private and fully local.")
        title_col.addWidget(subtitle)
        header.addLayout(title_col)
        header.addStretch(1)
        self._clear_btn = Button("Clear queue", ButtonVariant.GHOST, ButtonSize.SM, icon="trash-2", icon_size=14)
        self._clear_btn.clicked.connect(self._on_clear_queue)
        header.addWidget(self._clear_btn)
        layout.addLayout(header)

        # ---- upload area ------------------------------------------------
        self._upload = UploadArea()
        self._upload.files_dropped.connect(self._on_files_dropped)
        layout.addWidget(self._upload)

        # ---- two-column: queue + settings -------------------------------
        columns = QHBoxLayout()
        columns.setSpacing(16)

        # left: file queue card
        queue_card = Card("Selected Files")
        queue_layout = queue_card.body()
        self._table = FileTable([
            Column("file", "File", 0),
            Column("type", "Type", 90),
            Column("size", "Size", 100, align="right"),
            Column("status", "Status", 130),
            Column("actions", "", 44, sortable=False, align="center"),
        ])
        self._table.set_filter_options([("pdf", "PDF"), ("image", "Image")])
        self._table.context_menu(self._on_queue_menu)
        self._table.selection_changed.connect(lambda sel: self._update_bulk_bar(sel))
        queue_layout.addWidget(self._table)

        # bulk action bar under the table
        bulk = QHBoxLayout()
        bulk.setSpacing(8)
        self._bulk_label = CaptionText("")
        bulk.addWidget(self._bulk_label)
        bulk.addStretch(1)
        self._remove_selected_btn = Button("Remove selected", ButtonVariant.GHOST, ButtonSize.SM, icon="x", icon_size=13)
        self._remove_selected_btn.clicked.connect(self._on_remove_selected)
        self._remove_selected_btn.setEnabled(False)
        bulk.addWidget(self._remove_selected_btn)
        queue_layout.addLayout(bulk)

        # progress section inside the queue card
        self._progress_card = QFrame()
        self._progress_card.setProperty("ui", "cardSubtle")
        progress_layout = QVBoxLayout(self._progress_card)
        progress_layout.setContentsMargins(14, 12, 14, 12)
        progress_layout.setSpacing(8)
        progress_head = QHBoxLayout()
        self._progress_label = MutedText("Ready")
        progress_head.addWidget(self._progress_label)
        progress_head.addStretch(1)
        self._progress_pct = CaptionText("")
        progress_head.addWidget(self._progress_pct)
        progress_layout.addLayout(progress_head)
        self._progress_bar = ProgressBar()
        progress_layout.addWidget(self._progress_bar)
        # summary row (hidden until a run finishes)
        self._summary_row = QHBoxLayout()
        self._summary_row.setSpacing(8)
        progress_layout.addLayout(self._summary_row)
        self._progress_card.setVisible(False)
        queue_layout.addWidget(self._progress_card)

        columns.addWidget(queue_card, 3)

        # right: settings card
        settings_card = Card("Compression Settings")
        settings_layout = settings_card.body()
        self._build_settings(settings_layout)
        columns.addWidget(settings_card, 2)

        layout.addLayout(columns)
        scroll.setWidget(container)

    # ------------------------------------------------------------------ #
    def _build_settings(self, layout: QVBoxLayout) -> None:
        layout.addWidget(CaptionText("COMPRESSION LEVEL"))

        # level presets
        presets_row = QHBoxLayout()
        presets_row.setSpacing(8)
        self._presets: dict[CompressionLevel, LevelPreset] = {}
        for level in (CompressionLevel.HIGH, CompressionLevel.BALANCED, CompressionLevel.MAXIMUM):
            preset = LevelPreset(level)
            preset.selected.connect(self._on_level_selected)
            presets_row.addWidget(preset, 1)
            self._presets[level] = preset
        layout.addLayout(presets_row)
        self._select_level(CompressionLevel(self.controller.settings.default_level))

        layout.addSpacing(6)
        layout.addWidget(CaptionText("OUTPUT"))

        self._mode_dropdown = Dropdown()
        self._mode_dropdown.add_options([
            (OutputMode.SAME_DIR_SUFFIX.value, "Next to original — new file"),
            (OutputMode.OUTPUT_DIR.value, "Into a chosen folder"),
            (OutputMode.OVERWRITE.value, "Replace original file"),
        ])
        self._mode_dropdown.set_value(self.controller.settings.output_mode)
        self._mode_dropdown.currentIndexChanged.connect(self._on_mode_changed)
        layout.addWidget(self._mode_dropdown)

        self._suffix_row = QHBoxLayout()
        self._suffix_row.setSpacing(8)
        self._suffix_input = Input("suffix")
        self._suffix_input.setText("_compressed")
        self._suffix_row.addWidget(FieldLabel("Suffix", self._suffix_input))
        layout.addLayout(self._suffix_row)

        self._folder_row = QHBoxLayout()
        self._folder_row.setSpacing(8)
        self._folder_input = Input("Choose output folder…")
        self._folder_input.setText(self.controller.settings.output_dir)
        self._folder_input.setReadOnly(True)
        pick_btn = Button("Browse…", ButtonVariant.SECONDARY, ButtonSize.SM, icon="folder", icon_size=13)
        pick_btn.clicked.connect(self._pick_folder)
        self._folder_row.addWidget(self._folder_input, 1)
        self._folder_row.addWidget(pick_btn)
        layout.addLayout(self._folder_row)

        self._overwrite_note = CaptionText("The original file will be replaced. A backup is not created.")
        self._overwrite_note.setStyleSheet("color: palette(text); background: transparent;")
        layout.addWidget(self._overwrite_note)
        self._on_mode_changed()

        # advanced accordion
        layout.addSpacing(4)
        advanced = Accordion()
        item = advanced.add_item("Advanced options")
        adv = item.body()
        self._pdf_quality = self._slider_row(adv, "PDF image quality", 30, 95, 70)
        self._pdf_dpi = self._slider_row(adv, "Max PDF image DPI", 72, 300, 144, step=12)
        self._img_quality = self._slider_row(adv, "Image quality", 30, 95, 72)
        self._img_max_dim = self._spin_row(adv, "Max dimension (px, 0 = original)", 0, 10000, 0, step=100)
        self._strip_meta = self._switch_row(adv, "Strip metadata", True)
        self._keep_format = self._switch_row(adv, "Keep original format", True)
        layout.addLayout(advanced)

        layout.addSpacing(10)

        # action buttons
        self._compress_btn = Button("Compress Files", ButtonVariant.PRIMARY, ButtonSize.LG, icon="zap", icon_size=16)
        self._compress_btn.clicked.connect(self._on_compress)
        layout.addWidget(self._compress_btn)
        self._cancel_btn = Button("Cancel", ButtonVariant.OUTLINE, ButtonSize.LG, icon="x", icon_size=15)
        self._cancel_btn.clicked.connect(self._on_cancel)
        self._cancel_btn.setVisible(False)
        layout.addWidget(self._cancel_btn)

        layout.addStretch(1)

    # ------------------------------------------------------------------ #
    # helpers to build advanced controls
    # ------------------------------------------------------------------ #
    def _slider_row(self, layout, label: str, lo: int, hi: int, value: int, step: int = 1) -> "QSlider":
        from PySide6.QtWidgets import QSlider

        row = QHBoxLayout()
        row.setSpacing(8)
        caption = CaptionText(label)
        caption.setMinimumWidth(150)
        row.addWidget(caption)
        slider = QSlider(Qt.Horizontal)
        slider.setRange(lo, hi)
        slider.setValue(value)
        slider.setSingleStep(step)
        slider.setFixedWidth(120)
        row.addWidget(slider)
        value_label = CaptionText(str(value))
        row.addWidget(value_label)
        slider.valueChanged.connect(lambda v, l=value_label: l.setText(str(v)))
        row.addStretch(1)
        layout.addLayout(row)
        slider._value_label = value_label
        return slider

    def _spin_row(self, layout, label: str, lo: int, hi: int, value: int, step: int = 1) -> QSpinBox:
        row = QHBoxLayout()
        row.setSpacing(8)
        caption = CaptionText(label)
        caption.setMinimumWidth(150)
        row.addWidget(caption)
        spin = QSpinBox()
        spin.setRange(lo, hi)
        spin.setValue(value)
        spin.setSingleStep(step)
        spin.setFixedWidth(110)
        row.addWidget(spin)
        row.addStretch(1)
        layout.addLayout(row)
        return spin

    def _switch_row(self, layout, label: str, checked: bool) -> Switch:
        row = QHBoxLayout()
        row.setSpacing(8)
        caption = CaptionText(label)
        caption.setMinimumWidth(150)
        row.addWidget(caption)
        switch = Switch(checked)
        row.addWidget(switch)
        row.addStretch(1)
        layout.addLayout(row)
        return switch

    # ------------------------------------------------------------------ #
    # events
    # ------------------------------------------------------------------ #
    def _on_files_dropped(self, paths: list[str]) -> None:
        added = self.controller.add_paths(paths)
        unsupported = [
            p for p in paths
            if FileItem.from_path(p).kind == FileKind.UNSUPPORTED
        ]
        if unsupported:
            window = self.window()
            if hasattr(window, "toasts"):
                window.toasts.warning(
                    "Unsupported files skipped",
                    f"{len(unsupported)} file(s) are not PDF or image files.",
                )
        if added:
            self._refresh_queue()
            window = self.window()
            if hasattr(window, "toasts"):
                window.toasts.success(
                    "Files added",
                    f"{len(added)} file(s) added to the queue ({format_size(self.controller.queue_total_size())} total).",
                )

    def _on_clear_queue(self) -> None:
        if not self.controller.queue:
            return
        self.controller.clear_queue()
        self._status_by_path.clear()
        self._refresh_queue()

    def _on_remove_selected(self) -> None:
        indices = self._table.selected_indices()
        if not indices:
            return
        self.controller.remove_items(indices)
        self._refresh_queue()

    def _update_bulk_bar(self, selected: list[int]) -> None:
        self._remove_selected_btn.setEnabled(bool(selected))
        self._bulk_label.setText(f"{len(selected)} selected" if selected else "")

    def _on_queue_menu(self, selected: list[int], menu) -> None:
        if not selected:
            return
        path = self.controller.queue[selected[0]].path

        def open_folder():
            self._reveal_in_folder(path)

        menu.addAction(active_theme().icon("folder-open", size=15), "Open file location", open_folder)
        menu.addAction(active_theme().icon("copy", size=15), "Copy full path", lambda: self._copy_path(path))
        menu.addSeparator()
        menu.addAction(active_theme().icon("trash-2", size=15), "Remove from queue",
                       lambda: self._remove_paths(selected))

    def _remove_paths(self, indices: list[int]) -> None:
        self.controller.remove_items(indices)
        self._refresh_queue()

    def _reveal_in_folder(self, path: str) -> None:
        import subprocess
        import sys

        if sys.platform == "darwin":
            subprocess.Popen(["open", "-R", path])
        elif sys.platform == "win32":
            subprocess.Popen(["explorer", "/select,", path])
        else:
            subprocess.Popen(["xdg-open", str(Path(path).parent)])

    def _copy_path(self, path: str) -> None:
        from PySide6.QtWidgets import QApplication

        QApplication.clipboard().setText(path)

    # ------------------------------------------------------------------ #
    # settings interactions
    # ------------------------------------------------------------------ #
    def _on_level_selected(self, level: CompressionLevel) -> None:
        self._select_level(level)

    def _select_level(self, level: CompressionLevel) -> None:
        for lvl, preset in self._presets.items():
            preset.set_selected(lvl == level)
        self._level = level

    def _on_mode_changed(self) -> None:
        mode = self._mode_dropdown.current_value() or OutputMode.SAME_DIR_SUFFIX.value
        self._suffix_row.itemAt(0).widget().setVisible(mode == OutputMode.SAME_DIR_SUFFIX.value)
        self._folder_row.itemAt(0).widget().setVisible(mode == OutputMode.OUTPUT_DIR.value)
        self._overwrite_note.setVisible(mode == OutputMode.OVERWRITE.value)

    def _pick_folder(self) -> None:
        folder = QFileDialog.getExistingDirectory(self, "Choose output folder", self._folder_input.text() or str(Path.home()))
        if folder:
            self._folder_input.setText(folder)

    # ------------------------------------------------------------------ #
    # compression flow
    # ------------------------------------------------------------------ #
    def _on_compress(self) -> None:
        items = list(self.controller.queue)
        if not items:
            window = self.window()
            if hasattr(window, "toasts"):
                window.toasts.warning("Nothing to compress", "Add files to the queue first.")
            return

        options = self.controller.build_options()
        options.level = self._level
        mode = self._mode_dropdown.current_value() or OutputMode.SAME_DIR_SUFFIX.value
        options.output_mode = OutputMode(mode)
        options.output_dir = self._folder_input.text()
        options.suffix = self._suffix_input.text().strip() or "_compressed"
        # advanced overrides
        options.pdf.image_quality = self._pdf_quality.value()
        options.pdf.max_image_dpi = self._pdf_dpi.value()
        options.image.quality = self._img_quality.value()
        options.image.resize_max = self._img_max_dim.value()
        options.image.strip_metadata = self._strip_meta.isChecked()
        options.image.preserve_format = self._keep_format.isChecked()

        def proceed():
            self._start(items, options)

        if mode == OutputMode.OVERWRITE.value and self.controller.settings.overwrite_confirmation:
            confirm(
                self.window(),
                "Replace original files?",
                f"{len(items)} file(s) will be overwritten in place. This cannot be undone.",
                confirm_text="Replace files",
                danger=True,
                on_result=lambda ok: proceed() if ok else None,
            )
        else:
            proceed()

    def _start(self, items: list[FileItem], options) -> None:
        self._status_by_path = {item.path: JobStatus.RUNNING for item in items}
        self._results: list[JobResult] = []
        self._progress_card.setVisible(True)
        self._progress_bar.set_progress(0)
        self._progress_label.setText(f"Compressing {len(items)} file(s)…")
        self._clear_summary()
        self._compress_btn.setVisible(False)
        self._cancel_btn.setVisible(True)
        self._clear_btn.setEnabled(False)
        self._upload.setEnabled(False)

        self.controller.progress_updated.connect(self._on_progress)
        self.controller.compression_finished.connect(self._on_finished)
        self.controller.start_compression(items, options)
        self._refresh_queue()

    def _on_cancel(self) -> None:
        self.controller.cancel_compression()
        self._progress_label.setText("Cancelling…")

    def _on_progress(self, fraction: float, message: str) -> None:
        self._progress_bar.set_progress(fraction)
        self._progress_pct.setText(f"{int(fraction * 100)}%")
        self._progress_label.setText(message)

    def _on_finished(self, results: list[JobResult]) -> None:
        self._results = results
        for result in results:
            self._status_by_path[result.item.path] = result.status
        self._refresh_queue()
        self._show_summary(results)
        self._compress_btn.setVisible(True)
        self._cancel_btn.setVisible(False)
        self._clear_btn.setEnabled(True)
        self._upload.setEnabled(True)
        self.history_changed.emit()

        window = self.window()
        if not hasattr(window, "toasts"):
            return
        done = [r for r in results if r.status == JobStatus.DONE]
        failed = [r for r in results if r.status == JobStatus.FAILED]
        skipped = [r for r in results if r.status == JobStatus.SKIPPED]
        if done:
            saved = sum(r.original_size - r.compressed_size for r in done)
            pct = sum(r.savings_percent for r in done) / len(done)
            window.toasts.success(
                "Compression complete",
                f"{len(done)} file(s) compressed · {format_size(saved)} saved · {pct:.0f}% smaller on average.",
            )
        if failed:
            window.toasts.error("Some files failed", f"{len(failed)} file(s) could not be compressed.")
        if skipped:
            window.toasts.info("Files skipped", f"{len(skipped)} file(s) were already optimized.")

    def _show_summary(self, results: list[JobResult]) -> None:
        # clear old summary widgets
        while self._summary_row.count():
            item = self._summary_row.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        done = [r for r in results if r.status == JobStatus.DONE]
        if done:
            saved = sum(r.original_size - r.compressed_size for r in done)
            avg = sum(r.savings_percent for r in done) / len(done)
            self._summary_row.addWidget(Badge(f"{format_size(saved)} saved", BadgeVariant.SUCCESS, "trending-down"))
            self._summary_row.addWidget(Badge(f"{avg:.0f}% smaller", BadgeVariant.INFO, "percent"))
        failed = sum(1 for r in results if r.status == JobStatus.FAILED)
        if failed:
            self._summary_row.addWidget(Badge(f"{failed} failed", BadgeVariant.DANGER, "alert-circle"))
        self._summary_row.addStretch(1)

    def _clear_summary(self) -> None:
        while self._summary_row.count():
            item = self._summary_row.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

    # ------------------------------------------------------------------ #
    # queue rendering
    # ------------------------------------------------------------------ #
    def _refresh_queue(self) -> None:
        rows = []
        for item in self.controller.queue:
            status = self._status_by_path.get(item.path, JobStatus.PENDING)
            rows.append(self._row_for(item, status))
        self._table.set_rows(rows)

    def _row_for(self, item: FileItem, status: JobStatus) -> dict:
        kind_badge = BadgeVariant.DEFAULT if item.kind == FileKind.PDF else BadgeVariant.INFO
        status_cell, status_variant = self._status_cell(status)
        icon = "file-text" if item.kind == FileKind.PDF else "image"
        return {
            "file": {"kind": "text", "text": item.name, "secondary": str(Path(item.path).parent), "icon": icon, "sort": item.name.lower()},
            "type": {"kind": "badge", "text": "PDF" if item.kind == FileKind.PDF else "Image", "variant": kind_badge},
            "size": {"kind": "text", "text": format_size(item.size), "sort": item.size},
            "status": {"kind": "badge", "text": status_cell, "variant": status_variant, "icon": self._status_icon(status)},
            "actions": {"kind": "button", "icon": "x", "tooltip": "Remove", "callback": lambda p=item.path: self._remove_by_path(p)},
        }

    def _status_cell(self, status: JobStatus) -> tuple[str, str]:
        return {
            JobStatus.PENDING: ("Pending", "secondary"),
            JobStatus.RUNNING: ("Running…", "info"),
            JobStatus.DONE: ("Done", "success"),
            JobStatus.FAILED: ("Failed", "danger"),
            JobStatus.SKIPPED: ("Skipped", "warning"),
        }[status]

    @staticmethod
    def _status_icon(status: JobStatus) -> str | None:
        return {
            JobStatus.DONE: "check",
            JobStatus.FAILED: "alert-circle",
            JobStatus.SKIPPED: "info",
            JobStatus.RUNNING: "refresh-cw",
        }.get(status)

    def _remove_by_path(self, path: str) -> None:
        idx = next((i for i, item in enumerate(self.controller.queue) if item.path == path), None)
        if idx is not None:
            self.controller.remove_items([idx])
            self._refresh_queue()
