"""Use cases: application business logic, independent of any UI framework."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Callable, Optional

from app.core.entities import (
    AppSettings,
    CompressionOptions,
    FileItem,
    FileKind,
    HistoryEntry,
    JobResult,
    JobStatus,
    OutputMode,
)
from app.core.ports import (
    CompressError,
    Compressor,
    HistoryStore,
    ProgressCallback,
    SettingsStore,
)


class CompressorFactory:
    """Returns the right Compressor adapter for a file kind.

    The concrete registry is provided by the composition root (presentation
    layer) so the core stays framework-agnostic.
    """

    def get_compressor(self, kind: FileKind) -> Optional[Compressor]:
        raise NotImplementedError


def _unique_path(candidate: Path) -> Path:
    """Return *candidate*, or a numbered variant if it already exists."""
    if not candidate.exists():
        return candidate
    stem, suffix = candidate.stem, candidate.suffix
    for i in range(2, 10_000):
        alt = candidate.with_name(f"{stem} ({i}){suffix}")
        if not alt.exists():
            return alt
    return candidate


def resolve_output_path(src: str, options: CompressionOptions) -> str:
    """Compute the destination path for *src* under the given output mode."""
    src_path = Path(src)
    if options.output_mode == OutputMode.OVERWRITE:
        return str(src_path)
    if options.output_mode == OutputMode.OUTPUT_DIR and options.output_dir:
        out_dir = Path(options.output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        if out_dir.resolve() != src_path.parent.resolve():
            return str(_unique_path(out_dir / src_path.name))
        # output dir == source dir: fall back to suffix to avoid overwriting
    return str(_unique_path(src_path.with_name(f"{src_path.stem}{options.suffix}{src_path.suffix}")))


class CompressUseCase:
    """Compresses a batch of files, reporting progress per file."""

    def __init__(self, factory: CompressorFactory) -> None:
        self._factory = factory

    def run(
        self,
        items: list[FileItem],
        options: CompressionOptions,
        progress: Optional[ProgressCallback] = None,
        should_cancel: Optional[Callable[[], bool]] = None,
    ) -> list[JobResult]:
        results: list[JobResult] = []
        total = len(items)
        for index, item in enumerate(items):
            if should_cancel and should_cancel():
                break
            results.append(
                self._compress_one(item, options, index, total, progress)
            )
        return results

    def _compress_one(
        self,
        item: FileItem,
        options: CompressionOptions,
        index: int,
        total: int,
        progress: Optional[ProgressCallback],
    ) -> JobResult:
        # Max-size target must be strictly below the original size.
        target = options.target_bytes
        if target is not None and item.size <= target:
            return JobResult(
                item=item,
                status=JobStatus.FAILED,
                original_size=item.size,
                error=(
                    f"Target size {options.max_size_mb:g} MB is not smaller than the "
                    f"original ({_fmt_mb(item.size)})"
                ),
            )

        compressor = self._factory.get_compressor(item.kind)
        if compressor is None:
            return JobResult(
                item=item,
                status=JobStatus.FAILED,
                error=f"Unsupported file type: {item.kind.value.upper()}",
            )

        dst = resolve_output_path(item.path, options)
        in_place = Path(dst).resolve() == Path(item.path).resolve()
        work_path = dst
        if in_place:
            # Never read and write the same file: stage to a temp sibling.
            fd, work_path = tempfile.mkstemp(
                prefix=f".{Path(item.path).stem}-", suffix=".tmp", dir=str(Path(item.path).parent)
            )
            os.close(fd)
            os.unlink(work_path)

        def on_progress(fraction: float, message: str) -> None:
            if progress:
                progress(
                    (index + fraction) / max(total, 1),
                    f"{item.name} — {message}",
                )

        try:
            stats = compressor.compress(item.path, work_path, options, on_progress)
        except CompressError as exc:
            _safe_unlink(work_path)
            return JobResult(item=item, status=JobStatus.FAILED, error=str(exc))
        except Exception as exc:  # defensive: never crash the whole batch
            _safe_unlink(work_path)
            return JobResult(item=item, status=JobStatus.FAILED, error=f"Unexpected error: {exc}")

        # No-savings guard: don't ship a file that didn't get smaller.
        if stats.compressed_size >= item.size:
            _safe_unlink(work_path)
            return JobResult(
                item=item,
                status=JobStatus.SKIPPED,
                original_size=item.size,
                compressed_size=stats.compressed_size,
                error="File already optimized — no savings possible",
            )

        if in_place:
            try:
                os.replace(work_path, dst)
            except OSError as exc:
                _safe_unlink(work_path)
                return JobResult(item=item, status=JobStatus.FAILED, error=f"Cannot replace original: {exc}")

        return JobResult(
            item=item,
            status=JobStatus.DONE,
            output_path=dst,
            original_size=item.size,
            compressed_size=stats.compressed_size,
        )


def _safe_unlink(path: str) -> None:
    try:
        Path(path).unlink(missing_ok=True)
    except OSError:
        pass


def _fmt_mb(num_bytes: int) -> str:
    mb = num_bytes / (1024 * 1024)
    if mb >= 100:
        return f"{mb:.0f} MB"
    if mb >= 10:
        return f"{mb:.1f} MB"
    return f"{mb:.2f} MB"


class HistoryUseCase:
    def __init__(self, store: HistoryStore, limit: int = 200) -> None:
        self._store = store
        self._limit = limit

    def add(self, results: list[JobResult]) -> None:
        for result in results:
            if result.status == JobStatus.DONE:
                self._store.add(HistoryEntry.from_result(result))
        self._store.prune(self._limit)

    def list(self, limit: Optional[int] = None) -> list[HistoryEntry]:
        return self._store.list(limit or self._limit)

    def clear(self) -> None:
        self._store.clear()

    def remove(self, entry: HistoryEntry) -> None:
        """Remove a single entry (matched by timestamp + output path)."""
        remaining = [
            e for e in self._store.list()
            if not (e.timestamp == entry.timestamp and e.output_path == entry.output_path)
        ]
        self._store._write(remaining)


class SettingsUseCase:
    def __init__(self, store: SettingsStore) -> None:
        self._store = store

    def load(self) -> AppSettings:
        return self._store.load()

    def save(self, settings: AppSettings) -> None:
        self._store.save(settings)
