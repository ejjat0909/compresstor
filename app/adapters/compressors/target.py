"""Shared "compress until it fits a max size" ladder runner.

Compressors that want a target-size guarantee run a *quality ladder*: encode
the source repeatedly at progressively lower quality / resolution, stopping
at the first candidate that meets the byte budget, and keep the smallest
candidate overall as a best effort when the budget cannot be met.

Candidates are written to temp siblings of the destination so a failed or
oversized intermediate never clobbers the final file. The temp files are
removed once the best candidate is moved into place.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Callable, Optional

from app.core.entities import CompressStats
from app.core.ports import ProgressCallback

#: Callable[[step, tmp_path], CompressStats] — encode one ladder step.
StepRunner = Callable[[object, str], CompressStats]


def compress_to_target(
    run_step: StepRunner,
    dst: str,
    target_bytes: Optional[int],
    steps: list,
    progress: Optional[ProgressCallback] = None,
    progress_start: float = 0.3,
    progress_span: float = 0.6,
    label: str = "Adjusting quality",
) -> CompressStats:
    """Run *steps* through *run_step*, keeping the smallest candidate.

    Stops early once a candidate is at or below *target_bytes*. The best
    candidate is moved onto *dst*; leftover temp files are deleted.
    """
    best: Optional[CompressStats] = None
    tmp_paths: list[str] = []
    total = len(steps)

    for i, step in enumerate(steps):
        p = Path(dst)
        tmp = str(p.with_name(f"{p.stem}.q{i}{p.suffix}"))
        tmp_paths.append(tmp)
        if progress:
            progress(
                progress_start + progress_span * i / max(total, 1),
                f"{label} — pass {i + 1}/{total}",
            )
        stats = run_step(step, tmp)
        if best is None or stats.compressed_size < best.compressed_size:
            best = stats
        if target_bytes is not None and stats.compressed_size <= target_bytes:
            break

    assert best is not None  # steps is never empty
    for path in tmp_paths:
        if path != best.output_path:
            Path(path).unlink(missing_ok=True)
    os.replace(best.output_path, dst)
    return CompressStats(dst, best.original_size, Path(dst).stat().st_size)
