"""Application controller: composition root and UI <-> core glue.

Owns the use cases, the compression worker thread, and the current queue
state. Pages talk to this object, never to the core directly.
"""

from __future__ import annotations

import threading

from PySide6.QtCore import QObject, QThread, Qt, Signal, Slot

from app.adapters.compressors.registry import CompressorRegistry
from app.adapters.storage.json_stores import JsonHistoryStore, JsonSettingsStore
from app.core.entities import (
    AppSettings,
    CompressionLevel,
    CompressionOptions,
    FileItem,
    FileKind,
    JobResult,
)
from app.core.use_cases import CompressUseCase, HistoryUseCase, SettingsUseCase


class CompressWorker(QObject):
    """Runs the CompressUseCase on a background thread."""

    progress = Signal(float, str)
    finished = Signal(list)  # list[JobResult]

    def __init__(self, use_case: CompressUseCase) -> None:
        super().__init__()
        self._use_case = use_case
        self._cancel_event = threading.Event()

    @Slot(list, object)
    def run(self, items: list, options: CompressionOptions) -> None:
        self._cancel_event.clear()
        results = self._use_case.run(
            items,
            options,
            progress=lambda f, m: self.progress.emit(f, m),
            should_cancel=self._cancel_event.is_set,
        )
        self.finished.emit(results)

    @Slot()
    def cancel(self) -> None:
        self._cancel_event.set()


class AppController(QObject):
    """Single coordination point for the whole UI."""

    progress_updated = Signal(float, str)   # overall fraction, message
    compression_finished = Signal(list)     # list[JobResult]
    _run_requested = Signal(list, object)   # queues CompressWorker.run into its thread

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        settings_store = JsonSettingsStore()
        history_store = JsonHistoryStore()

        self.settings_uc = SettingsUseCase(settings_store)
        self.history_uc = HistoryUseCase(history_store)
        self.compress_uc = CompressUseCase(CompressorRegistry())

        self.settings: AppSettings = self.settings_uc.load()
        self.queue: list[FileItem] = []
        self.running = False

        # worker thread
        self._thread = QThread(self)
        self._worker = CompressWorker(self.compress_uc)
        self._worker.moveToThread(self._thread)
        self._thread.start()
        # invoke run() via a signal so it executes on the worker thread;
        # a direct call would block the main thread (frozen UI + dead modal).
        self._run_requested.connect(self._worker.run)

    # ------------------------------------------------------------------ #
    # Queue management
    # ------------------------------------------------------------------ #
    def add_paths(self, paths: list[str]) -> list[FileItem]:
        """Add supported files to the queue (dedupes existing paths)."""
        existing = {item.path for item in self.queue}
        added: list[FileItem] = []
        for path in paths:
            item = FileItem.from_path(path)
            if item.kind == FileKind.UNSUPPORTED:
                continue
            if item.path in existing or not item.size:
                continue
            self.queue.append(item)
            existing.add(item.path)
            added.append(item)
        return added

    def remove_items(self, indices: list[int]) -> list[FileItem]:
        removed = [self.queue[i] for i in sorted(indices, reverse=True)]
        for item in removed:
            self.queue.remove(item)
        return removed

    def clear_queue(self) -> None:
        self.queue.clear()

    def queue_total_size(self) -> int:
        return sum(item.size for item in self.queue)

    # ------------------------------------------------------------------ #
    # Compression
    # ------------------------------------------------------------------ #
    def build_options(self) -> CompressionOptions:
        s = self.settings
        return CompressionOptions(
            level=CompressionLevel(s.default_level),
            output_mode=s.output_mode,
            output_dir=s.output_dir,
        )

    def start_compression(self, items: list[FileItem], options: CompressionOptions) -> None:
        if self.running or not items:
            return
        self.running = True
        self._worker.progress.connect(self._on_progress)
        self._worker.finished.connect(self._on_finished)
        self._run_requested.emit(items, options)

    def cancel_compression(self) -> None:
        self._worker.cancel()

    # ------------------------------------------------------------------ #
    # Slots (run on the main thread via queued connections)
    # ------------------------------------------------------------------ #
    def _on_progress(self, fraction: float, message: str) -> None:
        self.progress_updated.emit(fraction, message)

    def _on_finished(self, results: list) -> None:
        self.running = False
        if self.settings.add_to_history:
            self.history_uc.add(results)
        self.compression_finished.emit(results)
        try:
            self._worker.progress.disconnect(self._on_progress)
            self._worker.finished.disconnect(self._on_finished)
        except (RuntimeError, TypeError):
            pass

    # ------------------------------------------------------------------ #
    # Settings
    # ------------------------------------------------------------------ #
    def save_settings(self, settings: AppSettings) -> None:
        self.settings = settings
        self.settings_uc.save(settings)

    def shutdown(self) -> None:
        self._worker.cancel()
        self._thread.quit()
        self._thread.wait(2000)
