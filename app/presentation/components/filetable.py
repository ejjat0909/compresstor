"""Filament-inspired table: sorting, search, filter, pagination, multi-select,
context menu, status badges and inline actions.

Cell value protocol (dict per cell):
    {"kind": "text",     "text": str, "secondary": str|None, "icon": str|None, "sort": any}
    {"kind": "badge",    "text": str, "variant": "success"|...}
    {"kind": "progress", "value": 0..1}
    {"kind": "button",   "icon": str, "tooltip": str, "callback": callable}
    {"kind": "space"}
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Optional

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QFrame,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from app.presentation.components.badge import Badge
from app.presentation.components.button import Button, ButtonSize, ButtonVariant, IconButton
from app.presentation.components.icons import IconLabel
from app.presentation.components.inputs import SearchBar
from app.presentation.components.progress import ProgressBar
from app.presentation.components.typography import CaptionText, NormalText, SecondaryText
from app.presentation.components.utils import format_size
from app.presentation.theme.registry import active_theme

PAGE_SIZE = 25


@dataclass
class Column:
    key: str
    title: str
    width: int = 0          # 0 -> stretch
    sortable: bool = True
    align: str = "left"     # left | right | center


class FileTable(QFrame):
    """A sortable, searchable, paginated table with row selection."""

    selection_changed = Signal(list)  # list of selected row indices (view space)

    def __init__(self, columns: list[Column] | None = None, parent=None) -> None:
        super().__init__(parent)
        self._columns: list[Column] = []
        self._rows: list[list[dict]] = []      # full data (list of row-cell dicts)
        self._view: list[int] = []             # indices into _rows for current view
        self._sort_key: str | None = None
        self._sort_desc = False
        self._search = ""
        self._filter: dict[str, str] = {}
        self._checked: set[int] = set()
        self._page = 0
        self._page_count = 1
        self._build()
        if columns:
            self.set_columns(columns)

    # ------------------------------------------------------------------ #
    def _build(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)

        # toolbar: search + filter dropdown
        toolbar = QHBoxLayout()
        toolbar.setSpacing(8)
        self._toolbar = toolbar
        self._search = SearchBar("Search files…")
        self._search.textChanged.connect(self._on_search)
        toolbar.addWidget(self._search, 1)
        self._filter_dropdown = None
        layout.addLayout(toolbar)

        self._table = QTableWidget()
        self._table.setShowGrid(False)
        self._table.setAlternatingRowColors(False)
        self._table.setSelectionMode(QTableWidget.ExtendedSelection)
        self._table.setSelectionBehavior(QTableWidget.SelectRows)
        self._table.verticalHeader().setVisible(False)
        self._table.verticalHeader().setDefaultSectionSize(44)
        self._table.setEditTriggers(QTableWidget.NoEditTriggers)
        self._table.setFocusPolicy(Qt.StrongFocus)
        self._table.setContextMenuPolicy(Qt.CustomContextMenu)
        self._table.customContextMenuRequested.connect(self._on_context_menu)
        self._table.itemSelectionChanged.connect(self._emit_selection)
        self._table.setMinimumHeight(240)
        layout.addWidget(self._table, 1)

        # pagination footer
        self._footer = QFrame()
        footer_layout = QHBoxLayout(self._footer)
        footer_layout.setContentsMargins(0, 0, 0, 0)
        footer_layout.setSpacing(6)
        self._count_label = CaptionText("")
        footer_layout.addWidget(self._count_label)
        footer_layout.addStretch(1)
        self._prev_btn = IconButton("chevron-left", "Previous page", size="iconSm", icon_size=14)
        self._prev_btn.clicked.connect(lambda: self._goto(self._page - 1))
        footer_layout.addWidget(self._prev_btn)
        self._page_label = CaptionText("")
        footer_layout.addWidget(self._page_label)
        self._next_btn = IconButton("chevron-right", "Next page", size="iconSm", icon_size=14)
        self._next_btn.clicked.connect(lambda: self._goto(self._page + 1))
        footer_layout.addWidget(self._next_btn)
        layout.addWidget(self._footer)

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #
    def set_columns(self, columns: list[Column]) -> None:
        self._columns = columns
        self._table.setColumnCount(len(columns) + 1)  # +1 checkbox column
        header = self._table.horizontalHeader()
        header.setStretchLastSection(False)
        header.setDefaultAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        header.setSectionsClickable(True)
        header.sectionClicked.connect(self._on_header_clicked)

        # header items
        for col, column in enumerate(columns, start=1):
            item = QTableWidgetItem(column.title)
            item.setTextAlignment(Qt.AlignLeft | Qt.AlignVCenter)
            self._table.setHorizontalHeaderItem(col, item)
        check_header = QTableWidgetItem()
        self._table.setHorizontalHeaderItem(0, check_header)
        self._table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Fixed)
        self._table.setColumnWidth(0, 36)
        for idx, column in enumerate(columns, start=1):
            mode = QHeaderView.Stretch if column.width == 0 else QHeaderView.Fixed
            self._table.horizontalHeader().setSectionResizeMode(idx, mode)
            if column.width:
                self._table.setColumnWidth(idx, column.width)

        self._header_check = QCheckBox()
        self._header_check.setToolTip("Select all on this page")
        self._header_check.stateChanged.connect(self._toggle_all)
        self._table.setCellWidget(0, 0, None)  # placeholder, replaced on populate
        # Put the select-all box in the corner by parenting it to the header:
        self._header_check.setParent(self._table.horizontalHeader().viewport())
        self._header_check.move(8, 6)

    def set_rows(self, rows: list[list[dict]]) -> None:
        self._rows = rows
        self._checked = set()
        self._page = 0
        self.refresh()

    def rows(self) -> list[list[dict]]:
        return self._rows

    def set_filter_options(self, options: list[tuple[str, str]]) -> None:
        """Add a filter dropdown: [(value, label), ...]. Value '' = all."""
        from app.presentation.components.dropdown import Dropdown

        if self._filter_dropdown is None:
            self._filter_dropdown = Dropdown()
            self._filter_dropdown.add_options([("", "All types")] + options)
            self._filter_dropdown.currentIndexChanged.connect(self._on_filter)
            self._toolbar.insertWidget(self._toolbar.count() - 1, self._filter_dropdown)
        else:
            self._filter_dropdown.clear()
            self._filter_dropdown.add_options([("", "All types")] + options)

    def selected_indices(self) -> list[int]:
        """Indices into the full (unfiltered) row list."""
        return sorted(self._checked)

    def set_checked(self, indices: list[int]) -> None:
        self._checked = set(indices)
        self._sync_checkboxes()
        self._emit_selection()

    def clear_selection(self) -> None:
        self._checked = set()
        self._table.clearSelection()
        self._sync_checkboxes()
        self._emit_selection()

    def context_menu(self, callback: Callable[[list[int], "QMenu"], None]) -> None:
        """Provide (selected_indices, menu) to populate the right-click menu."""
        self._menu_builder = callback

    def set_context_menu_policy(self, enabled: bool) -> None:
        self._table.setContextMenuPolicy(
            Qt.CustomContextMenu if enabled else Qt.DefaultContextMenu
        )

    # ------------------------------------------------------------------ #
    # Internal
    # ------------------------------------------------------------------ #
    def refresh(self) -> None:
        self._apply_filter()
        self._apply_sort()
        self._page_count = max(1, (len(self._view) + PAGE_SIZE - 1) // PAGE_SIZE)
        if self._page >= self._page_count:
            self._page = self._page_count - 1
        self._populate()

    def _filtered_rows(self) -> list[int]:
        out = []
        lowered = self._search.lower()
        for i, row in enumerate(self._rows):
            if self._filter:
                fv = self._filter.get("type")
                if fv:
                    cell = row.get("type") or {}
                    if cell.get("text", "") != fv:
                        continue
            if lowered:
                haystack = " ".join(
                    str(c.get("text", "")).lower()
                    for c in row.values()
                    if isinstance(c, dict) and c.get("kind") == "text"
                )
                if lowered not in haystack:
                    continue
            out.append(i)
        return out

    def _apply_filter(self) -> None:
        self._view = self._filtered_rows()

    def _apply_sort(self) -> None:
        if not self._sort_key:
            return
        col_idx = next((i for i, c in enumerate(self._columns) if c.key == self._sort_key), None)
        if col_idx is None or not self._columns[col_idx].sortable:
            return

        def sort_val(i: int):
            cell = self._rows[i][self._sort_key] if self._sort_key in self._rows[i] else {}
            if isinstance(cell, dict):
                if "sort" in cell and cell["sort"] is not None:
                    return cell["sort"]
                return str(cell.get("text", "")).lower()
            return str(cell).lower()

        self._view.sort(key=sort_val, reverse=self._sort_desc)

    def _on_header_clicked(self, section: int) -> None:
        if section == 0:
            return
        column = self._columns[section - 1]
        if not column.sortable:
            return
        if self._sort_key == column.key:
            self._sort_desc = not self._sort_desc
        else:
            self._sort_key = column.key
            self._sort_desc = False
        self._page = 0
        self._apply_sort()
        self._populate()
        self._update_header_indicators()

    def _update_header_indicators(self) -> None:
        for col, column in enumerate(self._columns, start=1):
            item = self._table.horizontalHeaderItem(col)
            if not item:
                continue
            if self._sort_key == column.key:
                arrow = " ↓" if self._sort_desc else " ↑"
                item.setText(column.title + arrow)
            else:
                item.setText(column.title)

    def _on_search(self, text: str) -> None:
        self._search = text
        self._page = 0
        self.refresh()

    def _on_filter(self, _index: int) -> None:
        if self._filter_dropdown:
            self._filter["type"] = self._filter_dropdown.current_value() or ""
        self._page = 0
        self.refresh()

    def _populate(self) -> None:
        table = self._table
        table.setUpdatesEnabled(False)
        table.clearContents()
        start = self._page * PAGE_SIZE
        page_rows = self._view[start : start + PAGE_SIZE]

        table.setRowCount(len(page_rows))
        for r, idx in enumerate(page_rows):
            row = self._rows[idx]
            # checkbox
            check = QCheckBox()
            check.setChecked(idx in self._checked)
            check.stateChanged.connect(lambda state, i=idx, rr=r: self._on_row_check(i, state))
            wrap = QWidget()
            wl = QHBoxLayout(wrap)
            wl.setContentsMargins(4, 0, 0, 0)
            wl.addWidget(check, 0, Qt.AlignLeft)
            table.setCellWidget(r, 0, wrap)

            for c, column in enumerate(self._columns, start=1):
                cell = row.get(column.key, {"kind": "space"})
                self._set_cell(r, c, cell, column)

        self._count_label.setText(f"{len(self._rows)} file(s)  ·  {len(self._view)} shown")
        self._page_label.setText(f"Page {self._page + 1} of {self._page_count}")
        self._prev_btn.setEnabled(self._page > 0)
        self._next_btn.setEnabled(self._page < self._page_count - 1)
        self._footer.setVisible(len(self._view) > PAGE_SIZE)
        table.setUpdatesEnabled(True)

    def _set_cell(self, r: int, c: int, cell: dict, column: Column) -> None:
        table = self._table
        kind = cell.get("kind", "text")
        align = column.align
        if kind == "text":
            icon = cell.get("icon")
            if icon:
                wrap = QWidget()
                lay = QHBoxLayout(wrap)
                lay.setContentsMargins(2, 0, 2, 0)
                lay.setSpacing(8)
                icon_lbl = IconLabel(icon, 15)
                lay.addWidget(icon_lbl)
                col = QVBoxLayout()
                col.setSpacing(1)
                text = NormalText(cell.get("text", ""))
                text.setStyleSheet("background: transparent;")
                col.addWidget(text)
                if cell.get("secondary"):
                    sub = SecondaryText(cell["secondary"])
                    sub.setStyleSheet("background: transparent;")
                    col.addWidget(sub)
                lay.addLayout(col)
                lay.addStretch(1)
                table.setCellWidget(r, c, wrap)
                return
            item = QTableWidgetItem(str(cell.get("text", "")))
            item.setData(Qt.UserRole, cell.get("sort"))
            flags = item.flags() & ~Qt.ItemIsEditable
            item.setFlags(flags)
            item.setToolTip(cell.get("tooltip", ""))
            item.setTextAlignment(Qt.AlignLeft | Qt.AlignVCenter)
            table.setItem(r, c, item)
        elif kind == "badge":
            badge = Badge(cell.get("text", ""), cell.get("variant", "default"), cell.get("icon"))
            wrap = QWidget()
            lay = QHBoxLayout(wrap)
            lay.setContentsMargins(2, 0, 2, 0)
            lay.addWidget(badge, 0, Qt.AlignLeft)
            table.setCellWidget(r, c, wrap)
        elif kind == "progress":
            bar = ProgressBar(cell.get("variant", "primary"))
            bar.setFixedWidth(120)
            bar.set_progress(cell.get("value", 0))
            wrap = QWidget()
            lay = QHBoxLayout(wrap)
            lay.setContentsMargins(2, 0, 2, 0)
            lay.addWidget(bar, 0, Qt.AlignLeft)
            table.setCellWidget(r, c, wrap)
        elif kind == "button":
            btn = IconButton(cell.get("icon", "x"), cell.get("tooltip", ""), size="iconSm", icon_size=13)
            btn.clicked.connect(cell["callback"])
            wrap = QWidget()
            lay = QHBoxLayout(wrap)
            lay.setContentsMargins(2, 0, 2, 0)
            lay.addWidget(btn, 0, Qt.AlignLeft)
            table.setCellWidget(r, c, wrap)
        elif kind == "space":
            table.setCellWidget(r, c, QWidget())

    # ------------------------------------------------------------------ #
    def _on_row_check(self, idx: int, state: int) -> None:
        if state == Qt.Checked:
            self._checked.add(idx)
        else:
            self._checked.discard(idx)
        self._sync_header_check()
        self._emit_selection()

    def _sync_checkboxes(self) -> None:
        for r in range(self._table.rowCount()):
            wrap = self._table.cellWidget(r, 0)
            if wrap:
                check = wrap.findChild(QCheckBox)
                if check:
                    idx = self._view[self._page * PAGE_SIZE + r] if (self._page * PAGE_SIZE + r) < len(self._view) else None
                    if idx is not None:
                        check.blockSignals(True)
                        check.setChecked(idx in self._checked)
                        check.blockSignals(False)
        self._sync_header_check()

    def _sync_header_check(self) -> None:
        page_indices = self._view[self._page * PAGE_SIZE : (self._page + 1) * PAGE_SIZE]
        if not page_indices:
            state = Qt.Unchecked
        elif all(i in self._checked for i in page_indices):
            state = Qt.Checked
        elif any(i in self._checked for i in page_indices):
            state = Qt.PartiallyChecked
        else:
            state = Qt.Unchecked
        self._header_check.blockSignals(True)
        self._header_check.setCheckState(state)
        self._header_check.blockSignals(False)

    def _toggle_all(self, state: int) -> None:
        page_indices = self._view[self._page * PAGE_SIZE : (self._page + 1) * PAGE_SIZE]
        if state == Qt.Checked:
            self._checked.update(page_indices)
        else:
            for i in page_indices:
                self._checked.discard(i)
        self._sync_checkboxes()
        self._emit_selection()

    def _emit_selection(self) -> None:
        self.selection_changed.emit(sorted(self._checked))

    def _on_context_menu(self, pos) -> None:
        builder = getattr(self, "_menu_builder", None)
        if not builder:
            return
        from PySide6.QtWidgets import QMenu

        item = self._table.itemAt(pos)
        row = item.row() if item else None
        selected = sorted(self._checked)
        if row is not None:
            idx = self._view[self._page * PAGE_SIZE + row] if (self._page * PAGE_SIZE + row) < len(self._view) else None
            if idx is not None and idx not in selected:
                selected = [idx]
        menu = QMenu(self)
        builder(selected, menu)
        menu.exec(self._table.viewport().mapToGlobal(pos))

    def _goto(self, page: int) -> None:
        if 0 <= page < self._page_count:
            self._page = page
            self._populate()
