"""Tests for the compression adapters (PDF + image) and storage stores."""

from __future__ import annotations

import io
import os
from pathlib import Path

import pytest

from app.adapters.compressors.image_compressor import ImageCompressor
from app.adapters.compressors.pdf_compressor import PdfCompressor
from app.adapters.compressors.registry import CompressorRegistry
from app.adapters.storage.json_stores import JsonHistoryStore, JsonSettingsStore
from app.core.entities import (
    AppSettings,
    CompressionLevel,
    CompressionOptions,
    FileItem,
    FileKind,
    HistoryEntry,
)
from app.core.use_cases import CompressUseCase, resolve_output_path
from app.core.ports import CompressError


# --------------------------------------------------------------------- #
# Fixtures
# --------------------------------------------------------------------- #
@pytest.fixture()
def sample_image(tmp_path: Path) -> Path:
    """A photographic-style JPEG with lots of compressible noise."""
    from PIL import Image, ImageDraw

    img = Image.new("RGB", (1600, 1200), (120, 130, 140))
    draw = ImageDraw.Draw(img)
    for i in range(2000):
        x, y = i * 7 % 1600, i * 11 % 1200
        draw.ellipse([x, y, x + 40, y + 40], fill=(i % 255, (i * 2) % 255, (i * 3) % 255))
    path = tmp_path / "photo.jpg"
    img.save(path, "JPEG", quality=100, subsampling=0)  # deliberately huge
    return path


@pytest.fixture()
def sample_png(tmp_path: Path) -> Path:
    from PIL import Image

    img = Image.new("RGBA", (800, 600), (200, 60, 60, 255))
    path = tmp_path / "logo.png"
    img.save(path, "PNG")
    return path


@pytest.fixture()
def sample_pdf(tmp_path: Path, sample_image: Path) -> Path:
    import fitz

    doc = fitz.open()
    for _ in range(3):
        page = doc.new_page(width=595, height=842)
        page.insert_text((72, 100), "Compresstor test document", fontsize=24)
        page.insert_image(fitz.Rect(72, 150, 400, 350), filename=str(sample_image))
    path = tmp_path / "doc.pdf"
    doc.save(path, garbage=0, deflate=False)
    doc.close()
    return path


# --------------------------------------------------------------------- #
# Image compression
# --------------------------------------------------------------------- #
class TestImageCompressor:
    def test_jpeg_compresses(self, sample_image: Path, tmp_path: Path):
        out = tmp_path / "out.jpg"
        stats = ImageCompressor().compress(
            str(sample_image), str(out), CompressionOptions()
        )
        assert out.exists()
        assert stats.compressed_size < stats.original_size
        assert stats.savings_percent > 10

    def test_png_quantized(self, sample_png: Path, tmp_path: Path):
        out = tmp_path / "out.png"
        stats = ImageCompressor().compress(
            str(sample_png), str(out), CompressionOptions(level=CompressionLevel.MAXIMUM)
        )
        assert out.exists()
        assert stats.compressed_size < stats.original_size

    def test_resize_max(self, sample_image: Path, tmp_path: Path):
        from PIL import Image as PILImage

        out = tmp_path / "out.jpg"
        opts = CompressionOptions()
        opts.image.resize_max = 800
        ImageCompressor().compress(str(sample_image), str(out), opts)
        with PILImage.open(out) as im:
            assert max(im.size) <= 800

    def test_convert_png_to_jpg(self, tmp_path: Path):
        from PIL import Image

        rgb = Image.new("RGB", (800, 600), (200, 60, 60))
        src = tmp_path / "flat.png"
        rgb.save(src, "PNG")
        out = tmp_path / "out.png"
        opts = CompressionOptions()
        opts.image.preserve_format = False
        stats = ImageCompressor().compress(str(src), str(out), opts)
        assert stats.output_path.endswith(".jpg")
        assert Path(stats.output_path).exists()

    def test_rgba_png_converts_to_webp(self, sample_png: Path, tmp_path: Path):
        out = tmp_path / "out.png"
        opts = CompressionOptions()
        opts.image.preserve_format = False
        stats = ImageCompressor().compress(str(sample_png), str(out), opts)
        assert stats.output_path.endswith(".webp")  # transparency preserved
        assert Path(stats.output_path).exists()

    def test_invalid_file_raises(self, tmp_path: Path):
        bogus = tmp_path / "fake.jpg"
        bogus.write_bytes(b"not an image at all")
        with pytest.raises(CompressError):
            ImageCompressor().compress(str(bogus), str(tmp_path / "o.jpg"), CompressionOptions())


# --------------------------------------------------------------------- #
# PDF compression
# --------------------------------------------------------------------- #
class TestPdfCompressor:
    def test_pdf_compresses(self, sample_pdf: Path, tmp_path: Path):
        out = tmp_path / "out.pdf"
        stats = PdfCompressor().compress(str(sample_pdf), str(out), CompressionOptions())
        assert out.exists()
        assert stats.compressed_size < stats.original_size
        assert stats.savings_percent > 20

    def test_pdf_still_readable(self, sample_pdf: Path, tmp_path: Path):
        import fitz

        out = tmp_path / "out.pdf"
        PdfCompressor().compress(str(sample_pdf), str(out), CompressionOptions())
        with fitz.open(str(out)) as doc:
            assert doc.page_count == 3
            assert doc.load_page(0).get_text().strip() == "Compresstor test document"

    def test_maximum_level_smaller_than_high(self, sample_pdf: Path, tmp_path: Path):
        high = tmp_path / "high.pdf"
        maxi = tmp_path / "max.pdf"
        PdfCompressor().compress(str(sample_pdf), str(high), CompressionOptions(level=CompressionLevel.HIGH))
        PdfCompressor().compress(str(sample_pdf), str(maxi), CompressionOptions(level=CompressionLevel.MAXIMUM))
        assert maxi.stat().st_size < high.stat().st_size

    def test_corrupt_pdf_raises(self, tmp_path: Path):
        bogus = tmp_path / "fake.pdf"
        bogus.write_bytes(b"%PDF-1.4 garbage not a real pdf")
        with pytest.raises(CompressError):
            PdfCompressor().compress(str(bogus), str(tmp_path / "o.pdf"), CompressionOptions())


# --------------------------------------------------------------------- #
# Use case orchestration
# --------------------------------------------------------------------- #
class TestUseCase:
    def test_batch_run(self, sample_image: Path, sample_pdf: Path, tmp_path: Path):
        registry = CompressorRegistry()
        use_case = CompressUseCase(registry)
        items = [
            FileItem.from_path(str(sample_image)),
            FileItem.from_path(str(sample_pdf)),
        ]
        opts = CompressionOptions(output_dir=str(tmp_path / "out"), suffix="-mini")
        results = use_case.run(items, opts)
        assert len(results) == 2
        assert all(r.status.value == "done" for r in results)
        assert all(Path(r.output_path).exists() for r in results)
        assert all(r.savings_percent > 0 for r in results)

    def test_unsupported_kind(self, tmp_path: Path):
        txt = tmp_path / "notes.txt"
        txt.write_text("hello")
        registry = CompressorRegistry()
        results = CompressUseCase(registry).run([FileItem.from_path(str(txt))], CompressionOptions())
        assert results[0].status.value == "failed"

    def test_output_path_modes(self, tmp_path: Path):
        src = tmp_path / "a.pdf"
        src.write_bytes(b"x")
        suffix_opts = CompressionOptions()
        assert resolve_output_path(str(src), suffix_opts) == str(tmp_path / "a-compressed.pdf")
        dir_opts = CompressionOptions(output_mode="directory", output_dir=str(tmp_path / "out"))
        assert resolve_output_path(str(src), dir_opts) == str(tmp_path / "out" / "a.pdf")
        overwrite_opts = CompressionOptions(output_mode="overwrite")
        assert resolve_output_path(str(src), overwrite_opts) == str(src)

    def test_no_savings_is_skipped(self, tmp_path: Path):
        """A file that cannot shrink must not produce output."""
        import fitz

        doc = fitz.open()
        page = doc.new_page(width=100, height=100)
        page.insert_text((10, 50), "tiny", fontsize=12)
        tiny = tmp_path / "tiny.pdf"
        doc.save(tiny, garbage=0)
        doc.close()

        # First pass legitimately shrinks it (deflate + garbage).
        first_out = tmp_path / "first"
        results = CompressUseCase(CompressorRegistry()).run(
            [FileItem.from_path(str(tiny))],
            CompressionOptions(output_mode="directory", output_dir=str(first_out)),
        )
        assert results[0].status.value == "done"
        assert (first_out / "tiny.pdf").exists()

        # Second pass on the already-optimized file must skip.
        optimized = first_out / "tiny.pdf"
        second_out = tmp_path / "second"
        results = CompressUseCase(CompressorRegistry()).run(
            [FileItem.from_path(str(optimized))],
            CompressionOptions(output_mode="directory", output_dir=str(second_out)),
        )
        assert results[0].status.value == "skipped"
        assert not (second_out / "tiny.pdf").exists()


# --------------------------------------------------------------------- #
# Storage
# --------------------------------------------------------------------- #
class TestStores:
    def test_settings_roundtrip(self, tmp_path: Path):
        store = JsonSettingsStore(tmp_path / "settings.json")
        settings = store.load()  # defaults
        assert settings.accent_color == "#2563eb"
        settings.theme = "dark"
        settings.accent_color = "#0ea5e9"
        store.save(settings)
        reloaded = store.load()
        assert reloaded.theme == "dark"
        assert reloaded.accent_color == "#0ea5e9"

    def test_history_roundtrip_and_prune(self, tmp_path: Path):
        store = JsonHistoryStore(tmp_path / "history.json")
        for i in range(5):
            store.add(
                HistoryEntry(
                    timestamp=float(i),
                    file_name=f"f{i}.pdf",
                    original_path=f"/x/f{i}.pdf",
                    output_path=f"/x/f{i}-c.pdf",
                    original_size=1000 + i,
                    compressed_size=500,
                    kind="pdf",
                    status="done",
                )
            )
        entries = store.list()
        assert len(entries) == 5
        assert entries[0].file_name == "f4.pdf"  # newest first
        store.prune(3)
        assert len(store.list()) == 3
        store.clear()
        assert store.list() == []
