"""History page: recent compression jobs with stats."""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFrame, QHBoxLayout, QScrollArea, QVBoxLayout, QWidget

from app.core.entities import HistoryEntry
from app.presentation.app_controller import AppController
from app.presentation.components.badge import Badge, BadgeVariant
from app.presentation.components.button import Button, ButtonSize, ButtonVariant
from app.presentation.components.card import Card
from app.presentation.components.filetable import Column, FileTable
from app.presentation.components.modal import confirm
from app.presentation.components.typography import SectionTitle, SecondaryText
from app.presentation.components.utils import format_size, format_timestamp
from app.presentation.theme.registry import active_theme


class HistoryPage(QWidget):
    def __init__(self, controller: AppController, parent=None) -> None:
        super().__init__(parent)
        self.controller = controller
        self._entries: list[HistoryEntry] = []
        self._build()
        self.refresh()

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

        # header
        header = QHBoxLayout()
        title_col = QVBoxLayout()
        title_col.setSpacing(2)
        title_col.addWidget(SectionTitle("History"))
        title_col.addWidget(SecondaryText("Everything you have compressed with Compresstor."))
        header.addLayout(title_col)
        header.addStretch(1)
        self._clear_btn = Button("Clear history", ButtonVariant.GHOST, ButtonSize.SM, icon="trash-2", icon_size=14)
        self._clear_btn.clicked.connect(self._on_clear)
        header.addWidget(self._clear_btn)
        layout.addLayout(header)

        # stats strip
        stats_card = Card()
        stats_layout = stats_card.body()
        stats_layout.setSpacing(0)
        stats_row = QHBoxLayout()
        stats_row.setSpacing(24)
        self._stat_files = self._stat_block(stats_row, "files", "0")
        self._stat_saved = self._stat_block(stats_row, "saved", "0 MB")
        self._stat_avg = self._stat_block(stats_row, "avg savings", "0%")
        self._stat_today = self._stat_block(stats_row, "today", "0")
        stats_row.addStretch(1)
        stats_layout.addLayout(stats_row)
        layout.addWidget(stats_card)

        # table card
        table_card = Card("Recent Activity")
        table_layout = table_card.body()
        self._table = FileTable([
            Column("file", "File", 0),
            Column("kind", "Type", 90),
            Column("before", "Before", 110, align="right"),
            Column("after", "After", 110, align="right"),
            Column("savings", "Saved", 120),
            Column("date", "Date", 170),
            Column("actions", "", 44, sortable=False, align="center"),
        ])
        self._table.set_filter_options([("pdf", "PDF"), ("image", "Image")])
        self._table.context_menu(self._on_menu)
        table_layout.addWidget(self._table)
        layout.addWidget(table_card, 1)

        scroll.setWidget(container)

    def _stat_block(self, row: QHBoxLayout, label: str, value: str) -> "QLabel":
        from app.presentation.components.typography import CaptionText

        block = QVBoxLayout()
        block.setSpacing(2)
        caption = CaptionText(label.upper())
        block.addWidget(caption)
        from app.presentation.components.typography import NormalText

        value_label = NormalText(value)
        value_label.setStyleSheet("font-size: 18pt; font-weight: 700; background: transparent; color: palette(text);")
        block.addWidget(value_label)
        row.addLayout(block)
        return value_label

    # ------------------------------------------------------------------ #
    def refresh(self) -> None:
        self._entries = self.controller.history_uc.list()
        rows = [self._row_for(e) for e in self._entries]
        self._table.set_rows(rows)
        self._update_stats()

    def _update_stats(self) -> None:
        done = [e for e in self._entries if e.status == "done"]
        total_saved = sum(max(0, e.original_size - e.compressed_size) for e in done)
        avg = (sum(e.savings_percent for e in done) / len(done)) if done else 0.0
        from datetime import datetime

        today = sum(1 for e in self._entries if datetime.fromtimestamp(e.timestamp).date() == datetime.now().date())
        self._stat_files.setText(str(len(done)))
        self._stat_saved.setText(format_size(total_saved))
        self._stat_avg.setText(f"{avg:.0f}%")
        self._stat_today.setText(str(today))

    def _row_for(self, entry: HistoryEntry) -> dict:
        icon = "file-text" if entry.kind == "pdf" else "image"
        kind_variant = BadgeVariant.DEFAULT if entry.kind == "pdf" else BadgeVariant.INFO
        status_variant = BadgeVariant.SUCCESS if entry.status == "done" else (
            BadgeVariant.DANGER if entry.status == "failed" else BadgeVariant.WARNING)
        return {
            "file": {"kind": "text", "text": entry.file_name, "secondary": entry.output_path, "icon": icon, "sort": entry.file_name.lower()},
            "kind": {"kind": "badge", "text": "PDF" if entry.kind == "pdf" else "Image", "variant": kind_variant},
            "before": {"kind": "text", "text": format_size(entry.original_size), "sort": entry.original_size},
            "after": {"kind": "text", "text": format_size(entry.compressed_size), "sort": entry.compressed_size},
            "savings": {"kind": "badge", "text": f"{entry.savings_percent:.0f}% smaller", "variant": status_variant,
                        "icon": "trending-down" if entry.savings_percent > 0 else None},
            "date": {"kind": "text", "text": format_timestamp(entry.timestamp), "sort": entry.timestamp},
            "actions": {"kind": "button", "icon": "more-horizontal", "tooltip": "Actions", "callback": lambda e=entry: self._entry_actions(e)},
        }

    # ------------------------------------------------------------------ #
    def _on_menu(self, selected: list[int], menu) -> None:
        if not selected:
            return
        entry = self._entries[selected[0]]
        menu.addAction(active_theme().icon("folder-open", size=15), "Open file location",
                       lambda: self._open_location(entry.output_path))
        menu.addAction(active_theme().icon("copy", size=15), "Copy output path",
                       lambda: self._copy(entry.output_path))
        menu.addSeparator()
        menu.addAction(active_theme().icon("trash-2", size=15), "Remove from history",
                       lambda: self._remove_entry(entry))

    def _entry_actions(self, entry: HistoryEntry) -> None:
        from PySide6.QtWidgets import QApplication, QMenu

        menu = QMenu(self)
        menu.addAction(active_theme().icon("folder-open", size=15), "Open file location",
                       lambda: self._open_location(entry.output_path))
        menu.addAction(active_theme().icon("copy", size=15), "Copy output path",
                       lambda: self._copy(entry.output_path))
        menu.addSeparator()
        menu.addAction(active_theme().icon("trash-2", size=15), "Remove from history",
                       lambda: self._remove_entry(entry))
        button = self.sender()
        if button:
            menu.exec(button.mapToGlobal(button.rect().bottomLeft()))

    def _remove_entry(self, entry: HistoryEntry) -> None:
        self.controller.history_uc.remove(entry)
        self.refresh()

    def _open_location(self, path: str) -> None:
        import subprocess
        import sys

        p = Path(path)
        if not p.exists():
            p = Path(path).parent if Path(path).parent.exists() else Path.home()
        if sys.platform == "darwin":
            subprocess.Popen(["open", "-R", str(p)])
        elif sys.platform == "win32":
            subprocess.Popen(["explorer", "/select,", str(p)])
        else:
            subprocess.Popen(["xdg-open", str(p.parent)])

    def _copy(self, text: str) -> None:
        from PySide6.QtWidgets import QApplication

        QApplication.clipboard().setText(text)

    def _on_clear(self) -> None:
        if not self._entries:
            return
        confirm(
            self.window(),
            "Clear history?",
            "All compression history will be removed. This cannot be undone.",
            confirm_text="Clear history",
            danger=True,
            on_result=lambda ok: self._clear_now() if ok else None,
        )

    def _clear_now(self) -> None:
        self.controller.history_uc.clear()
        self.refresh()
