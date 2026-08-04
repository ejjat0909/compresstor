"""Engine CLI — JSON-lines bridge between the Flutter frontend and the
Python compression engine.

Protocol: see ``docs/engine-protocol.md``. One subcommand per invocation:

    python -m app.engine.engine_cli compress  < request.json
    python -m app.engine.engine_cli history   < request.json
    python -m app.engine.engine_cli settings  < request.json

Every event on stdout is a single JSON object followed by ``\\n``. Non-fatal
warnings go to stderr; the frontend ignores stderr for parsing.
"""

from __future__ import annotations

import argparse
import json
import signal
import sys
from dataclasses import asdict
from pathlib import Path
from threading import Event
from typing import Any, Callable, TextIO

from app.core.entities import (
    AppSettings,
    CompressionLevel,
    CompressionOptions,
    FileItem,
    HistoryEntry,
    ImageOptions,
    JobResult,
    OutputMode,
    PdfOptions,
)
from app.core.ports import HistoryStore, SettingsStore
from app.core.use_cases import (
    CompressUseCase,
    CompressorFactory,
    HistoryUseCase,
    SettingsUseCase,
)


# --------------------------------------------------------------------- I/O --

class EventWriter:
    """Writes one JSON object per line to *stream* and flushes eagerly."""

    def __init__(self, stream: TextIO) -> None:
        self._stream = stream

    def emit(self, event: dict[str, Any]) -> None:
        self._stream.write(json.dumps(event, separators=(",", ":")) + "\n")
        self._stream.flush()


def _read_request(stream: TextIO) -> dict[str, Any]:
    raw = stream.read()
    if not raw.strip():
        return {}
    return json.loads(raw)


# ----------------------------------------------------------------- mapping --

def _parse_options(payload: dict[str, Any]) -> CompressionOptions:
    """Convert JSON options into a CompressionOptions dataclass."""

    level = CompressionLevel(payload.get("level", "balanced"))
    output_mode = OutputMode(payload.get("output_mode", "suffix"))

    pdf_payload = payload.get("pdf")
    image_payload = payload.get("image")
    pdf = PdfOptions(**pdf_payload) if pdf_payload else None
    image = ImageOptions(**image_payload) if image_payload else None

    max_size = payload.get("max_size_mb")
    return CompressionOptions(
        level=level,
        output_mode=output_mode,
        output_dir=payload.get("output_dir", ""),
        suffix=payload.get("suffix", "_compressed"),
        max_size_mb=float(max_size) if max_size else None,
        pdf=pdf,
        image=image,
    )


def _parse_items(payload: list[dict[str, Any]]) -> list[FileItem]:
    items: list[FileItem] = []
    for entry in payload:
        path = entry.get("path")
        if not path:
            continue
        items.append(FileItem.from_path(path))
    return items


def _job_result_to_dict(result: JobResult) -> dict[str, Any]:
    return {
        "path": result.item.path,
        "name": result.item.name,
        "kind": result.item.kind.value,
        "size": result.item.size,
        "status": result.status.value,
        "output_path": result.output_path,
        "original_size": result.original_size,
        "compressed_size": result.compressed_size,
        "error": result.error,
    }


def _history_entry_to_dict(entry: HistoryEntry) -> dict[str, Any]:
    return asdict(entry)


def _settings_to_dict(settings: AppSettings) -> dict[str, Any]:
    return asdict(settings)


# ---------------------------------------------------------- compressor DI --

def _make_registry() -> CompressorFactory:
    """Import the registry lazily so subcommands that do not need PyMuPDF/
    Pillow (history, settings) stay fast."""
    from app.adapters.compressors.registry import CompressorRegistry

    return CompressorRegistry()


def _make_stores() -> tuple[SettingsStore, HistoryStore]:
    from app.adapters.storage.json_stores import JsonHistoryStore, JsonSettingsStore

    return JsonSettingsStore(), JsonHistoryStore()


# ------------------------------------------------------------- subcommands --

def cmd_compress(
    request: dict[str, Any],
    writer: EventWriter,
    cancel: Event,
    *,
    factory: CompressorFactory | None = None,
    history_store: HistoryStore | None = None,
) -> int:
    items = _parse_items(request.get("items", []))
    options = _parse_options(request.get("options", {}))
    add_to_history = bool(request.get("add_to_history", True))

    total = len(items)
    writer.emit({"type": "started", "total": total})
    if total == 0:
        writer.emit({"type": "finished", "results": []})
        return 0

    factory = factory or _make_registry()
    use_case = CompressUseCase(factory)

    # Per-file progress: we track which file's events we're seeing by peeking
    # at the aggregate fraction; the use case already emits (index+frac)/total.
    def progress(fraction: float, message: str) -> None:
        approx_index = min(int(fraction * total), total - 1)
        writer.emit(
            {
                "type": "progress",
                "index": approx_index,
                "fraction": fraction,
                "message": message,
            }
        )

    results = use_case.run(
        items,
        options,
        progress=progress,
        should_cancel=cancel.is_set,
    )

    # Emit per-file completion events after the fact — the use case does not
    # currently expose a hook for that, so we synthesise them here to make
    # the UI's job trivial.
    for index, result in enumerate(results):
        writer.emit(
            {
                "type": "file_done",
                "index": index,
                "result": _job_result_to_dict(result),
            }
        )

    payload = [_job_result_to_dict(r) for r in results]

    if add_to_history and results:
        if history_store is None:
            settings_store, history = _make_stores()
        else:
            settings_store, _ = _make_stores()
            history = history_store
        try:
            limit = settings_store.load().history_limit
        except Exception:
            limit = 200
        HistoryUseCase(history, limit=limit).add(results)

    if cancel.is_set():
        writer.emit({"type": "cancelled", "completed": len(results)})
        writer.emit({"type": "finished", "results": payload})
        return 2

    writer.emit({"type": "finished", "results": payload})
    return 0


def cmd_history(
    request: dict[str, Any],
    writer: EventWriter,
    *,
    history_store: HistoryStore | None = None,
    settings_store: SettingsStore | None = None,
) -> int:
    if history_store is None or settings_store is None:
        settings_store, history_store = _make_stores()

    action = request.get("action", "list")

    if action == "list":
        limit = int(request.get("limit") or settings_store.load().history_limit)
        entries = history_store.list(limit)
        writer.emit(
            {
                "type": "history",
                "entries": [_history_entry_to_dict(e) for e in entries],
            }
        )
        return 0

    if action == "add":
        for payload in request.get("entries", []):
            history_store.add(HistoryEntry(**payload))
        history_store.prune(settings_store.load().history_limit)
        writer.emit({"type": "ok"})
        return 0

    if action == "clear":
        history_store.clear()
        writer.emit({"type": "ok"})
        return 0

    if action == "remove":
        timestamp = float(request.get("timestamp", 0.0))
        output_path = request.get("output_path", "")
        remaining = [
            e for e in history_store.list()
            if not (e.timestamp == timestamp and e.output_path == output_path)
        ]
        # HistoryStore has no public replace method; reuse the JSON store hook.
        write = getattr(history_store, "_write", None)
        if write is not None:
            write(remaining)
        writer.emit({"type": "ok"})
        return 0

    writer.emit({"type": "error", "message": f"Unknown history action: {action}"})
    return 1


def cmd_settings(
    request: dict[str, Any],
    writer: EventWriter,
    *,
    settings_store: SettingsStore | None = None,
) -> int:
    if settings_store is None:
        settings_store, _ = _make_stores()

    action = request.get("action", "get")

    if action == "get":
        writer.emit({"type": "settings", "settings": _settings_to_dict(settings_store.load())})
        return 0

    if action == "set":
        current = settings_store.load()
        payload = request.get("settings", {})
        merged = AppSettings(**{**_settings_to_dict(current), **{k: v for k, v in payload.items() if hasattr(current, k)}})
        settings_store.save(merged)
        writer.emit({"type": "settings", "settings": _settings_to_dict(merged)})
        return 0

    writer.emit({"type": "error", "message": f"Unknown settings action: {action}"})
    return 1


# -------------------------------------------------------------------- main --

def _install_signal_handlers(cancel: Event) -> None:
    def _handler(signum, _frame):  # noqa: ANN001
        cancel.set()

    signal.signal(signal.SIGINT, _handler)
    try:
        signal.signal(signal.SIGTERM, _handler)
    except (AttributeError, ValueError):
        pass  # Windows/thread contexts


def run(
    argv: list[str] | None = None,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
) -> int:
    parser = argparse.ArgumentParser(prog="engine_cli")
    parser.add_argument("subcommand", choices=["compress", "history", "settings"])
    args = parser.parse_args(argv)

    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    writer = EventWriter(stdout)
    cancel = Event()
    _install_signal_handlers(cancel)

    try:
        request = _read_request(stdin)
    except json.JSONDecodeError as exc:
        writer.emit({"type": "error", "message": f"Malformed JSON request: {exc}"})
        return 1

    if args.subcommand == "compress":
        return cmd_compress(request, writer, cancel)
    if args.subcommand == "history":
        return cmd_history(request, writer)
    if args.subcommand == "settings":
        return cmd_settings(request, writer)

    writer.emit({"type": "error", "message": f"Unknown subcommand: {args.subcommand}"})
    return 1


if __name__ == "__main__":
    sys.exit(run())
