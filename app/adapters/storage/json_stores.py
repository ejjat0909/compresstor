"""JSON persistence for application settings and compression history."""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

from app.core.entities import AppSettings, HistoryEntry
from app.core.ports import HistoryStore, SettingsStore

log = logging.getLogger(__name__)

APP_DIR_NAME = "Compresstor"


def app_data_dir() -> Path:
    """Platform-appropriate data directory (respects XDG/APPDATA/Library)."""
    env = os.environ.get("COMPRESSTOR_DATA_DIR")
    if env:
        return Path(env)
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    elif sys_platform() == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    path = base / APP_DIR_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def sys_platform() -> str:
    import sys

    return sys.platform


class JsonSettingsStore(SettingsStore):
    """Persists AppSettings as JSON in the app data directory."""

    DEFAULTS = {
        "theme": "system",
        "accent_color": "#2563eb",
        "history_limit": 200,
        "default_level": "balanced",
        "output_mode": "suffix",
        "output_dir": "",
        "overwrite_confirmation": True,
        "add_to_history": True,
    }

    def __init__(self, path: Path | None = None) -> None:
        self._path = path or (app_data_dir() / "settings.json")

    def load(self) -> AppSettings:
        data: dict = {}
        if self._path.exists():
            try:
                data = json.loads(self._path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError) as exc:
                log.warning("Corrupt settings file, using defaults: %s", exc)
        merged = {**self.DEFAULTS, **{k: v for k, v in data.items() if k in self.DEFAULTS}}
        return AppSettings(**merged)

    def save(self, settings: AppSettings) -> None:
        payload = {
            "theme": settings.theme,
            "accent_color": settings.accent_color,
            "history_limit": settings.history_limit,
            "default_level": settings.default_level,
            "output_mode": settings.output_mode,
            "output_dir": settings.output_dir,
            "overwrite_confirmation": settings.overwrite_confirmation,
            "add_to_history": settings.add_to_history,
        }
        self._path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        tmp.replace(self._path)


class JsonHistoryStore(HistoryStore):
    """Persists compression history as a JSON array (newest first)."""

    def __init__(self, path: Path | None = None) -> None:
        self._path = path or (app_data_dir() / "history.json")

    def list(self, limit: int | None = None) -> list[HistoryEntry]:
        entries = self._read()
        if limit is not None:
            entries = entries[:limit]
        return entries

    def add(self, entry: HistoryEntry) -> None:
        entries = self._read()
        entries.insert(0, entry)
        self._write(entries)

    def clear(self) -> None:
        self._write([])

    def prune(self, limit: int) -> None:
        entries = self._read()
        if len(entries) > limit:
            self._write(entries[:limit])

    # ------------------------------------------------------------------ #
    def _read(self) -> list[HistoryEntry]:
        if not self._path.exists():
            return []
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            return [HistoryEntry(**item) for item in data if isinstance(item, dict)]
        except (json.JSONDecodeError, OSError, TypeError) as exc:
            log.warning("Corrupt history file, ignoring: %s", exc)
            return []

    def _write(self, entries: list[HistoryEntry]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = [
            {
                "timestamp": e.timestamp,
                "file_name": e.file_name,
                "original_path": e.original_path,
                "output_path": e.output_path,
                "original_size": e.original_size,
                "compressed_size": e.compressed_size,
                "kind": e.kind,
                "status": e.status,
            }
            for e in entries
        ]
        tmp = self._path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        tmp.replace(self._path)
