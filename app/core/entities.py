"""Domain entities for Compresstor.

This module is part of the core layer and MUST remain free of any UI
framework imports (Qt, etc.) so it can be tested in isolation and reused
by any frontend.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


class FileKind(str, Enum):
    PDF = "pdf"
    IMAGE = "image"
    UNSUPPORTED = "unsupported"


class JobStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    SKIPPED = "skipped"


class CompressionLevel(str, Enum):
    """Preset levels mapped to concrete options by the compressors."""

    HIGH = "high"          # best quality, modest savings
    BALANCED = "balanced"  # good trade-off (default)
    MAXIMUM = "maximum"    # smallest size, visible quality loss possible


class OutputMode(str, Enum):
    SAME_DIR_SUFFIX = "suffix"    # original_dir / name_compressed.ext
    OUTPUT_DIR = "directory"      # chosen output dir, same file name
    OVERWRITE = "overwrite"       # replace the original file


# Supported file extensions -> kind
PDF_EXTENSIONS = {".pdf"}
IMAGE_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".gif",
}


def detect_kind(path: str | Path) -> FileKind:
    suffix = Path(path).suffix.lower()
    if suffix in PDF_EXTENSIONS:
        return FileKind.PDF
    if suffix in IMAGE_EXTENSIONS:
        return FileKind.IMAGE
    return FileKind.UNSUPPORTED


@dataclass(frozen=True)
class FileItem:
    """A file the user added to the compression queue."""

    path: str
    kind: FileKind
    size: int
    name: str = ""

    def __post_init__(self) -> None:
        if not self.name:
            object.__setattr__(self, "name", Path(self.path).name)

    @classmethod
    def from_path(cls, path: str | Path) -> "FileItem":
        p = Path(path)
        return cls(
            path=str(p),
            kind=detect_kind(p),
            size=p.stat().st_size if p.exists() else 0,
            name=p.name,
        )


@dataclass
class PdfOptions:
    """Options for PDF compression."""

    image_quality: int = 70       # JPEG quality for re-encoded images (1-100)
    max_image_dpi: int = 144      # downscale embedded images above this DPI
    remove_metadata: bool = True
    deflate: bool = True
    garbage: int = 4              # PyMuPDF garbage level (1-4)


@dataclass
class ImageOptions:
    """Options for image compression."""

    quality: int = 72             # lossy quality (1-100), applies to jpg/webp
    resize_max: int = 0           # 0 = keep original dimensions
    preserve_format: bool = True  # keep the original file format
    strip_metadata: bool = True


@dataclass
class CompressionOptions:
    """Full user-facing compression settings.

    Presets for *level* are applied automatically; individual fields of
    *pdf* / *image* can be overridden afterwards.
    """

    level: CompressionLevel = CompressionLevel.BALANCED
    output_mode: OutputMode = OutputMode.SAME_DIR_SUFFIX
    output_dir: str = ""
    suffix: str = "_compressed"
    pdf: PdfOptions | None = None
    image: ImageOptions | None = None

    def __post_init__(self) -> None:
        preset = _LEVEL_PRESETS[self.level]
        self.pdf = self.pdf or preset[0]
        self.image = self.image or preset[1]


_LEVEL_PRESETS: dict[CompressionLevel, tuple[PdfOptions, ImageOptions]] = {
    CompressionLevel.HIGH: (
        PdfOptions(image_quality=85, max_image_dpi=180),
        ImageOptions(quality=82),
    ),
    CompressionLevel.BALANCED: (
        PdfOptions(image_quality=70, max_image_dpi=144),
        ImageOptions(quality=72),
    ),
    CompressionLevel.MAXIMUM: (
        PdfOptions(image_quality=50, max_image_dpi=100),
        ImageOptions(quality=50),
    ),
}


@dataclass(frozen=True)
class CompressStats:
    """Result statistics for a single compressed file."""

    output_path: str
    original_size: int
    compressed_size: int

    @property
    def savings(self) -> int:
        return max(0, self.original_size - self.compressed_size)

    @property
    def savings_percent(self) -> float:
        if self.original_size <= 0:
            return 0.0
        return round(self.savings / self.original_size * 100, 1)


@dataclass
class JobResult:
    """Outcome of compressing one file."""

    item: FileItem
    status: JobStatus
    output_path: str = ""
    original_size: int = 0
    compressed_size: int = 0
    error: str = ""

    @property
    def savings_percent(self) -> float:
        if self.original_size <= 0:
            return 0.0
        return round(max(0, self.original_size - self.compressed_size) / self.original_size * 100, 1)


@dataclass
class HistoryEntry:
    """One row in the recent-history store."""

    timestamp: float
    file_name: str
    original_path: str
    output_path: str
    original_size: int
    compressed_size: int
    kind: str
    status: str

    @classmethod
    def from_result(cls, result: JobResult) -> "HistoryEntry":
        return cls(
            timestamp=time.time(),
            file_name=result.item.name,
            original_path=result.item.path,
            output_path=result.output_path,
            original_size=result.original_size,
            compressed_size=result.compressed_size,
            kind=result.item.kind.value,
            status=result.status.value,
        )

    @property
    def savings_percent(self) -> float:
        if self.original_size <= 0:
            return 0.0
        return round(
            max(0, self.original_size - self.compressed_size) / self.original_size * 100, 1
        )


@dataclass
class AppSettings:
    """Persisted application settings (theme, defaults, behaviour)."""

    theme: str = "system"              # system | light | dark
    accent_color: str = "#2563eb"      # blue-600 default
    history_limit: int = 200
    default_level: str = "balanced"
    output_mode: str = "suffix"
    output_dir: str = ""
    overwrite_confirmation: bool = True
    add_to_history: bool = True
