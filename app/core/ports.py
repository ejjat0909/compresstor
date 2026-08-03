"""Ports (interfaces) for the core layer.

Adapters in the infrastructure layer implement these. The core layer only
depends on these abstractions (dependency inversion).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Callable, Optional

from app.core.entities import AppSettings, CompressionOptions, CompressStats, HistoryEntry


ProgressCallback = Callable[[float, str], None]
"""progress callback: (fraction 0..1, human-readable message)"""


class Compressor(ABC):
    """Compresses a single file from source to destination."""

    @abstractmethod
    def compress(
        self,
        src: str,
        dst: str,
        options: CompressionOptions,
        progress: Optional[ProgressCallback] = None,
    ) -> CompressStats:
        """Compress *src* into *dst*.

        Raises CompressError on failure. The progress callback receives
        (fraction, message) updates.
        """


class SettingsStore(ABC):
    @abstractmethod
    def load(self) -> AppSettings: ...

    @abstractmethod
    def save(self, settings: AppSettings) -> None: ...


class HistoryStore(ABC):
    @abstractmethod
    def list(self, limit: Optional[int] = None) -> list[HistoryEntry]: ...

    @abstractmethod
    def add(self, entry: HistoryEntry) -> None: ...

    @abstractmethod
    def clear(self) -> None: ...

    @abstractmethod
    def prune(self, limit: int) -> None: ...


class CompressError(Exception):
    """Raised by compressors when a file cannot be compressed."""
