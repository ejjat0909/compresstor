"""Parity regression guard (Phase 5) — same fixtures through the old app
engine path (CompressUseCase directly, as PySide6 wired it) and the new engine
CLI (what the Flutter app spawns) must produce IDENTICAL results:

  - output SIZES identical for every file kind (the documented parity contract)
  - output BYTES identical for deterministic formats (JPEG/WebP/TIFF)

PDFs (random /ID per save) and low-quality PNGs (randomized Floyd–Steinberg
dither) are compared by size only — see scripts/parity_check.py.

Run:  python -m pytest tests/test_parity.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import parity_check as parity  # noqa: E402


@pytest.fixture(scope="module")
def parity_rows(tmp_path_factory) -> list[dict]:
    tmp = tmp_path_factory.mktemp("parity")
    parity.os.environ["COMPRESSTOR_DATA_DIR"] = str(tmp / "data")
    results = parity.run_parity(tmp, parity.LEVELS)
    assert results, "parity comparison produced no rows"
    return results


def test_every_row_parity_holds(parity_rows: list[dict]) -> None:
    for row in parity_rows:
        assert row["ok"], f"{row['file']} @ {row['level']} failed: {row}"


def test_sizes_match_for_all_files(parity_rows: list[dict]) -> None:
    for row in parity_rows:
        assert row["size_match"], (
            f"size mismatch {row['file']} @ {row['level']}: "
            f"{row['old_size']} != {row['new_size']}"
        )


def test_deterministic_image_output_bytes_identical(parity_rows: list[dict]) -> None:
    # Byte-for-byte equality is only expected for deterministic formats
    # (JPEG/WebP/TIFF). PDF and low-quality PNG are intentionally excluded
    # (random /ID and Floyd–Steinberg dither respectively — see
    # scripts/parity_check.py).
    checked = [r for r in parity_rows if r["bytes_note"] == "bytes"]
    assert checked, "expected at least one deterministic (JPEG/WebP/TIFF) row"
    for row in checked:
        assert row["hash_match"], (
            f"output bytes differ {row['file']} @ {row['level']}: "
            f"old vs new outputs are not byte-identical"
        )