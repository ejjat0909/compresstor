"""Tests for the engine CLI (JSON-lines bridge)."""

from __future__ import annotations

import io
import json
from pathlib import Path

import pytest
from PIL import Image, ImageDraw

from app.adapters.storage.json_stores import JsonHistoryStore, JsonSettingsStore
from app.engine import engine_cli
from app.engine.engine_cli import EventWriter, cmd_compress, cmd_history, cmd_settings
from threading import Event


# --------------------------------------------------------------- fixtures --

@pytest.fixture()
def image_file(tmp_path: Path) -> Path:
    """A moderately compressible JPEG on disk."""
    img = Image.new("RGB", (800, 600), (120, 130, 140))
    draw = ImageDraw.Draw(img)
    for i in range(400):
        x, y = i * 7 % 800, i * 11 % 600
        draw.ellipse([x, y, x + 20, y + 20], fill=(i % 255, (i * 2) % 255, (i * 3) % 255))
    path = tmp_path / "sample.jpg"
    img.save(path, format="JPEG", quality=95)
    return path


@pytest.fixture()
def stores(tmp_path: Path) -> tuple[JsonSettingsStore, JsonHistoryStore]:
    return (
        JsonSettingsStore(path=tmp_path / "settings.json"),
        JsonHistoryStore(path=tmp_path / "history.json"),
    )


def _collect_events(buf: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in buf.getvalue().splitlines() if line.strip()]


# --------------------------------------------------------------- settings --

def test_settings_get_returns_defaults(stores):
    settings, _ = stores
    out = io.StringIO()
    rc = cmd_settings({"action": "get"}, EventWriter(out), settings_store=settings)
    assert rc == 0
    events = _collect_events(out)
    assert events[0]["type"] == "settings"
    assert events[0]["settings"]["default_level"] == "balanced"


def test_settings_set_persists_and_returns_merged(stores):
    settings_store, _ = stores
    out = io.StringIO()
    rc = cmd_settings(
        {"action": "set", "settings": {"accent_color": "#ff00aa", "history_limit": 42}},
        EventWriter(out),
        settings_store=settings_store,
    )
    assert rc == 0
    events = _collect_events(out)
    assert events[-1]["settings"]["accent_color"] == "#ff00aa"
    assert events[-1]["settings"]["history_limit"] == 42
    # Round-trip: reload from disk.
    reloaded = JsonSettingsStore(path=settings_store._path).load()
    assert reloaded.history_limit == 42


def test_settings_unknown_action_reports_error(stores):
    settings_store, _ = stores
    out = io.StringIO()
    rc = cmd_settings({"action": "nope"}, EventWriter(out), settings_store=settings_store)
    assert rc == 1
    assert _collect_events(out)[0]["type"] == "error"


# ---------------------------------------------------------------- history --

def test_history_list_empty(stores):
    settings_store, history_store = stores
    out = io.StringIO()
    rc = cmd_history(
        {"action": "list", "limit": 10},
        EventWriter(out),
        history_store=history_store,
        settings_store=settings_store,
    )
    assert rc == 0
    events = _collect_events(out)
    assert events[0] == {"type": "history", "entries": []}


def test_history_add_and_clear_roundtrip(stores):
    settings_store, history_store = stores
    entry = {
        "timestamp": 1.0,
        "file_name": "a.pdf",
        "original_path": "/tmp/a.pdf",
        "output_path": "/tmp/a_c.pdf",
        "original_size": 100,
        "compressed_size": 50,
        "kind": "pdf",
        "status": "done",
    }
    add_out = io.StringIO()
    cmd_history(
        {"action": "add", "entries": [entry]},
        EventWriter(add_out),
        history_store=history_store,
        settings_store=settings_store,
    )
    assert _collect_events(add_out)[0] == {"type": "ok"}

    list_out = io.StringIO()
    cmd_history(
        {"action": "list"},
        EventWriter(list_out),
        history_store=history_store,
        settings_store=settings_store,
    )
    assert _collect_events(list_out)[0]["entries"][0]["file_name"] == "a.pdf"

    clear_out = io.StringIO()
    cmd_history(
        {"action": "clear"},
        EventWriter(clear_out),
        history_store=history_store,
        settings_store=settings_store,
    )
    assert _collect_events(clear_out)[0] == {"type": "ok"}
    assert history_store.list() == []


def test_history_remove_matches_by_timestamp_and_output(stores):
    settings_store, history_store = stores
    e1 = {
        "timestamp": 1.0, "file_name": "a.pdf", "original_path": "/tmp/a.pdf",
        "output_path": "/tmp/a_c.pdf", "original_size": 100, "compressed_size": 50,
        "kind": "pdf", "status": "done",
    }
    e2 = {**e1, "timestamp": 2.0, "output_path": "/tmp/b_c.pdf"}
    cmd_history({"action": "add", "entries": [e1, e2]}, EventWriter(io.StringIO()),
                history_store=history_store, settings_store=settings_store)

    cmd_history(
        {"action": "remove", "timestamp": 2.0, "output_path": "/tmp/b_c.pdf"},
        EventWriter(io.StringIO()),
        history_store=history_store,
        settings_store=settings_store,
    )
    remaining = history_store.list()
    assert len(remaining) == 1
    assert remaining[0].timestamp == 1.0


# --------------------------------------------------------------- compress --

def test_compress_image_emits_full_event_sequence(image_file, stores):
    settings_store, history_store = stores
    out = io.StringIO()
    request = {
        "items": [{"path": str(image_file)}],
        "options": {"level": "balanced", "output_mode": "suffix", "suffix": "_c"},
        "add_to_history": False,
    }
    rc = cmd_compress(
        request,
        EventWriter(out),
        Event(),
        history_store=history_store,
    )
    events = _collect_events(out)
    types = [e["type"] for e in events]

    assert rc == 0
    assert types[0] == "started"
    assert types[-1] == "finished"
    assert "file_done" in types
    assert events[-1]["results"][0]["status"] in {"done", "skipped"}

    # Output file exists when done.
    result = events[-1]["results"][0]
    if result["status"] == "done":
        assert Path(result["output_path"]).exists()


def test_compress_empty_batch_finishes_cleanly(stores):
    _, history_store = stores
    out = io.StringIO()
    rc = cmd_compress(
        {"items": [], "options": {}, "add_to_history": False},
        EventWriter(out),
        Event(),
        history_store=history_store,
    )
    assert rc == 0
    events = _collect_events(out)
    assert events[0] == {"type": "started", "total": 0}
    assert events[-1] == {"type": "finished", "results": []}


def test_compress_unsupported_file_marks_failed(tmp_path: Path, stores):
    _, history_store = stores
    bogus = tmp_path / "x.txt"
    bogus.write_text("not an image")
    out = io.StringIO()
    rc = cmd_compress(
        {
            "items": [{"path": str(bogus)}],
            "options": {"level": "balanced"},
            "add_to_history": False,
        },
        EventWriter(out),
        Event(),
        history_store=history_store,
    )
    assert rc == 0  # per-file failure, not process failure
    events = _collect_events(out)
    result = events[-1]["results"][0]
    assert result["status"] == "failed"
    assert "Unsupported" in result["error"]


def test_compress_cancel_before_first_file(image_file, stores):
    _, history_store = stores
    out = io.StringIO()
    cancel = Event()
    cancel.set()
    rc = cmd_compress(
        {
            "items": [{"path": str(image_file)}],
            "options": {"level": "balanced"},
            "add_to_history": False,
        },
        EventWriter(out),
        cancel,
        history_store=history_store,
    )
    assert rc == 2
    types = [e["type"] for e in _collect_events(out)]
    assert "cancelled" in types


# ------------------------------------------------------------- top-level --

def test_run_rejects_malformed_json():
    stdin = io.StringIO("{not json")
    stdout = io.StringIO()
    rc = engine_cli.run(["settings"], stdin=stdin, stdout=stdout)
    assert rc == 1
    assert _collect_events(stdout)[0]["type"] == "error"


def test_run_settings_get_end_to_end(tmp_path, monkeypatch):
    # Point the JSON store at a temp dir via COMPRESSTOR_DATA_DIR.
    monkeypatch.setenv("COMPRESSTOR_DATA_DIR", str(tmp_path))
    stdin = io.StringIO('{"action":"get"}')
    stdout = io.StringIO()
    rc = engine_cli.run(["settings"], stdin=stdin, stdout=stdout)
    assert rc == 0
    events = _collect_events(stdout)
    assert events[0]["type"] == "settings"
