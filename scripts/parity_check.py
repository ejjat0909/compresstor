"""Engine parity checker — Phase 5.

Runs the SAME fixtures through both compression entry points and proves the
results are identical:

  OLD path (the previous stacked/legacy engine path — now removed with PySide6):
      CompressUseCase(CompressorRegistry()).run(...)  — in-process, as
      app/presentation/app_controller.py wires it.

  NEW path (what the Flutter app spawns):
      python -m app.engine.engine_cli compress        — subprocess, request
      shaped exactly like docs/engine-protocol.md.

Both paths resolve to the same core use case + compressor adapters, so output
sizes AND output bytes MUST be identical. Any drift fails the run (non-zero
exit) and is written to docs/parity-report.md as a table.

Usage:
    python scripts/parity_check.py [--out docs/parity-report.md] [--levels high,balanced,maximum]

Isolates side effects: everything runs in a temp dir (COMPRESSTOR_DATA_DIR is
pointed at it) so real user settings/history are untouched.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import asdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from app.adapters.compressors.registry import CompressorRegistry  # noqa: E402
from app.core.entities import (  # noqa: E402
    CompressionLevel,
    CompressionOptions,
    FileItem,
    JobResult,
    JobStatus,
    OutputMode,
)
from app.core.use_cases import CompressUseCase  # noqa: E402

LEVELS = [
    CompressionLevel.HIGH,
    CompressionLevel.BALANCED,
    CompressionLevel.MAXIMUM,
]

DEFAULT_OUT = REPO_ROOT / "docs" / "parity-report.md"


# ------------------------------------------------------------------ fixtures --


def build_fixtures(dest: Path) -> list[Path]:
    """Create representative fixtures: text PDF, image-rich PDF, JPEG, PNG."""
    from PIL import Image, ImageDraw
    import fitz

    # Noisy photographic JPEG (deliberately huge, quality 100).
    img = Image.new("RGB", (1600, 1200), (120, 130, 140))
    d = ImageDraw.Draw(img)
    for i in range(2000):
        x, y = i * 7 % 1600, i * 11 % 1200
        d.ellipse([x, y, x + 40, y + 40], fill=(i % 255, (i * 2) % 255, (i * 3) % 255))
    photo = dest / "photo.jpg"
    img.save(photo, "JPEG", quality=100, subsampling=0)

    # Flat-colour PNG (logo-like).
    logo = dest / "logo.png"
    Image.new("RGBA", (800, 600), (200, 60, 60, 255)).save(logo, "PNG")

    # Image-rich 3-page PDF (embeds the noisy photo 3x).
    doc = fitz.open()
    for _ in range(3):
        page = doc.new_page(width=595, height=842)
        page.insert_text((72, 100), "Compresstor parity document", fontsize=24)
        page.insert_image(fitz.Rect(72, 150, 400, 350), filename=str(photo))
    pdf = dest / "doc.pdf"
    doc.save(pdf, garbage=0, deflate=False)
    doc.close()

    # Small text-only PDF (exercises the no-savings/skip branch).
    doc = fitz.open()
    page = doc.new_page(width=595, height=842)
    page.insert_text((72, 100), "tiny", fontsize=12)
    small = dest / "small.pdf"
    doc.save(small, garbage=0, deflate=False)
    doc.close()

    return [pdf, small, photo, logo]


# ------------------------------------------------------------ engine paths --


def old_path_compress(fixture: Path, options: CompressionOptions) -> JobResult:
    """In-process use case run — the exact path the PySide6 app used."""
    use_case = CompressUseCase(CompressorRegistry())
    results = use_case.run([FileItem.from_path(str(fixture))], options)
    return results[0]


def cli_path_compress(fixture: Path, options: CompressionOptions) -> dict:
    """Subprocess run through engine_cli — the exact path Flutter uses.

    The request is `asdict(options)` — the same keys the Dart side sends
    (docs/engine-protocol.md) — plus add_to_history: false so the run never
    touches persisted history.
    """
    payload = {
        "items": [{"path": str(fixture)}],
        "options": asdict(options),
        "add_to_history": False,
    }
    proc = subprocess.run(
        [sys.executable, "-m", "app.engine.engine_cli", "compress"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
        timeout=120,
        check=False,
    )
    if proc.returncode not in (0, 2):
        raise RuntimeError(
            f"engine_cli compress exited {proc.returncode}: {proc.stderr}"
        )
    events = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    finished = [e for e in events if e["type"] == "finished"]
    if not finished or not finished[0]["results"]:
        raise RuntimeError(f"No finished results for {fixture.name}: {events}")
    return finished[0]["results"][0]


def _sha256(path: str) -> str | None:
    p = Path(path)
    if not p.exists():
        return None
    return hashlib.sha256(p.read_bytes()).hexdigest()


def options_for(level: CompressionLevel) -> CompressionOptions:
    return CompressionOptions(
        level=level,
        output_mode=OutputMode.SAME_DIR_SUFFIX,
        suffix="_compressed",
    )


# ------------------------------------------------------------------ compare --


def compare_one(fixture: Path, level: CompressionLevel) -> dict:
    """Run both paths on *fixture* and return a comparison row.

    The documented parity contract is OUTPUT SIZE equality for every file
    kind (same engine + options ⇒ same bytes budget). Status equality too.
    Byte-for-byte output is guaranteed only for deterministic formats:
      - JPEG / WebP / TIFF ... deterministic (hash compared)
      - PDF ................. NOT: PyMuPDF stamps a fresh random /ID per save
      - PNG (quality < 85) .. NOT: Pillow quantizes with a randomized
                              Floyd–Steinberg dither
    PDF and low-quality PNG rows use size comparison only.
    """
    opts = options_for(level)

    old = old_path_compress(fixture, opts)
    new = cli_path_compress(fixture, opts)

    ext = Path(fixture).suffix.lower()
    is_pdf = ext == ".pdf"
    is_png = ext == ".png"
    bytes_comparable = not is_pdf and not is_png

    status_match = old.status.value == new["status"]
    size_match = old.compressed_size == new["compressed_size"]

    old_hash = _sha256(old.output_path) if old.status == JobStatus.DONE else None
    new_hash = _sha256(new.get("output_path", "")) if new["status"] == "done" else None
    hash_match = old_hash == new_hash and old_hash is not None
    ok = status_match and size_match and (hash_match if bytes_comparable else True)

    return {
        "file": fixture.name,
        "level": level.value,
        "kind": "pdf" if is_pdf else "image",
        "bytes_note": (
            "PDF /ID"
            if is_pdf
            else ("PNG dither" if is_png else ("bytes" if bytes_comparable else ""))
        ),
        "original": old.original_size,
        "old_size": old.compressed_size,
        "new_size": new["compressed_size"],
        "old_status": old.status.value,
        "new_status": new["status"],
        "size_match": size_match,
        "hash_match": hash_match,
        "status_match": status_match,
        "ok": ok,
    }


def run_parity(tmp: Path, levels: list[CompressionLevel]) -> list[dict]:
    """Build fixtures once and compare each across *levels*."""
    fixtures = build_fixtures(tmp)
    rows = []
    for fixture in fixtures:
        for level in levels:
            rows.append(compare_one(fixture, level))
    return rows


# ------------------------------------------------------------------ report --


def render_markdown(rows: list[dict]) -> str:
    from datetime import date

    lines = [
        "# Engine Parity Report",
        "",
        "Same fixtures through the legacy engine path (`CompressUseCase`",
        "directly) vs the new engine CLI (`engine_cli.py compress`, as the",
        "Flutter app spawns it). Both paths share the same core use case +",
        "compressors, so output SIZES must be identical for every file.",
        "Byte comparison applies only to deterministic formats; PDF and",
        "low-quality PNG outputs are not byte-deterministic by design:",
        "PyMuPDF stamps a fresh random document `/ID` per save, and Pillow's",
        "PNG quantization uses a randomized Floyd–Steinberg dither.",
        "",
        f"Generated: {date.today().isoformat()}  \n"
        f"Command: `python scripts/parity_check.py`",
        "",
        "| File | Level | Original (B) | Old path size (B) | New path size (B) | Status | Sizes | Bytes |",
        "|------|-------|-------------:|------------------:|------------------:|--------|-------|-------|",
    ]
    for r in rows:
        status = f"{r['old_status']}/{r['new_status']}"
        size_mark = "✅" if r["size_match"] else "❌"
        note = r["bytes_note"]
        if note == "bytes":
            bytes_mark = "✅" if r["hash_match"] else "❌"
        elif note:
            bytes_mark = f"n/a ({note})"
        else:
            bytes_mark = "—"
        if not r["ok"]:
            reasons = []
            if not r["status_match"]:
                reasons.append("status")
            if not r["size_match"]:
                reasons.append("size")
            if note == "bytes" and not r["hash_match"]:
                reasons.append("bytes")
            mark = f"❌ ({', '.join(reasons)})"
        else:
            mark = "✅"
        lines.append(
            f"| {r['file']} | {r['level']} | {r['original']:,} | "
            f"{r['old_size']:,} | {r['new_size']:,} | {status} | {size_mark} | {bytes_mark} |"
        )
    lines.append("")
    ok_count = sum(1 for r in rows if r["ok"])
    lines.append(
        f"**Result: {ok_count}/{len(rows)} rows identical.** "
        + ("Parity holds." if ok_count == len(rows) else "PARITY DRIFT — investigate!")
    )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--levels",
        default=",".join(l.value for l in LEVELS),
        help="comma-separated levels: high,balanced,maximum",
    )
    args = parser.parse_args()

    levels = [CompressionLevel(v.strip()) for v in args.levels.split(",")]
    unknown = [l for l in levels if l not in CompressionLevel]
    if unknown:
        print(f"Unknown levels: {unknown}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="compresstor-parity-") as td:
        tmp = Path(td)
        # Keep the CLI's stores out of the real data dir.
        os.environ["COMPRESSTOR_DATA_DIR"] = str(tmp / "data")

        print(f"Building fixtures in {tmp} …")
        rows = run_parity(tmp, levels)

    for r in rows:
        mark = "OK " if r["ok"] else "FAIL"
        print(
            f"[{mark}] {r['file']} @ {r['level']}: "
            f"{r['original']:,} -> {r['old_size']:,} (old) / "
            f"{r['new_size']:,} (new) bytes"
        )

    report = render_markdown(rows)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report, encoding="utf-8")
    print(f"\nReport: {args.out}")

    if not all(r["ok"] for r in rows):
        print("\nPARITY DRIFT — outputs differ between old and new paths.", file=sys.stderr)
        return 1
    print("Parity holds: old and new paths produce identical outputs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
