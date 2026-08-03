"""Compressor registry: maps file kinds to concrete compressor adapters."""

from __future__ import annotations

from app.core.entities import FileKind
from app.core.ports import Compressor
from app.core.use_cases import CompressorFactory
from app.adapters.compressors.image_compressor import ImageCompressor
from app.adapters.compressors.pdf_compressor import PdfCompressor


class CompressorRegistry(CompressorFactory):
    """Production registry wiring kinds to their compressors."""

    def __init__(self) -> None:
        self._pdf = PdfCompressor()
        self._image = ImageCompressor()

    def get_compressor(self, kind: FileKind) -> Compressor | None:
        if kind == FileKind.PDF:
            return self._pdf
        if kind == FileKind.IMAGE:
            return self._image
        return None
