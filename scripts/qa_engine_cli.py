"""Headless QA harness for the engine CLI (Phase 1 addition).

Runs one compress + one settings + one history round-trip through
``python -m app.engine.engine_cli``, verifies the response event shapes,
and prints a short summary. Non-zero exit code on any protocol violation.

Usage:  python scripts/qa_engine_cli.py

Isolates side effects: uses a temp settings/history dir and a temp sample
file so the developer's real Compresstor data is untouched.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))


def _run(subcommand: str, payload: dict, env: dict[str, str]) -> list[dict]:
    """Invoke the CLI with *payload*, return decoded stdout events."""
    proc = subprocess.run(
        [sys.executable, "-m", "app.engine.engine_cli", subcommand],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
        cwd=str(REPO_ROOT),
        timeout=120,
        check=False,
    )
    if proc.returncode not in (0, 2):
        raise RuntimeError(
            f"engine_cli {subcommand} exited {proc.returncode}: {proc.stderr}"
        )
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


def _make_sample_pdf(dest: Path) -> Path:
    from PIL import Image, ImageDraw
    import fitz

    photo = dest / "photo.jpg"
    img = Image.new("RGB", (1400, 1000), (110, 120, 135))
    d = ImageDraw.Draw(img)
    for i in range(1200):
        x, y = i * 9 % 1400, i * 13 % 1000
        d.ellipse([x, y, x + 50, y + 50], fill=(i % 255, (i * 2) % 255, (i * 4) % 255))
    img.save(photo, "JPEG", quality=98, subsampling=0)

    doc = fitz.open()
    for i in range(3):
        page = doc.new_page(width=595, height=842)
        page.insert_text((72, 90), f"QA page {i + 1}", fontsize=20)
        page.insert_image(fitz.Rect(72, 140, 420, 400), filename=str(photo))
    pdf = dest / "qa.pdf"
    doc.save(pdf, garbage=0, deflate=False)
    doc.close()
    return pdf


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="compresstor-cli-qa-") as td:
        tmp = Path(td)
        env = {**os.environ, "COMPRESSTOR_DATA_DIR": str(tmp / "data")}

        # --- settings roundtrip --------------------------------------------
        settings = _run("settings", {"action": "get"}, env)
        assert settings[0]["type"] == "settings", settings
        print("settings/get:", settings[0]["settings"]["default_level"])

        _run("settings", {"action": "set", "settings": {"history_limit": 5}}, env)
        settings2 = _run("settings", {"action": "get"}, env)
        assert settings2[0]["settings"]["history_limit"] == 5

        # --- compress ------------------------------------------------------
        pdf = _make_sample_pdf(tmp)
        events = _run(
            "compress",
            {
                "items": [{"path": str(pdf)}],
                "options": {"level": "balanced", "output_mode": "suffix", "suffix": "_c"},
                "add_to_history": True,
            },
            env,
        )
        types = [e["type"] for e in events]
        assert types[0] == "started"
        assert types[-1] == "finished"
        assert "file_done" in types
        result = events[-1]["results"][0]
        print(
            f"compress: {result['name']} {result['original_size']} -> "
            f"{result['compressed_size']} bytes ({result['status']})"
        )

        # --- history -------------------------------------------------------
        history = _run("history", {"action": "list", "limit": 10}, env)
        assert history[0]["type"] == "history"
        print(f"history: {len(history[0]['entries'])} entry(ies)")

        print("engine CLI QA: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
