"""PDF compression adapter using PyMuPDF (fitz).

Strategy:
  1. Re-encode every embedded image as JPEG at the configured quality,
     downscaling images whose effective DPI exceeds *max_image_dpi*.
  2. Keep the original image when re-encoding would not shrink it.
  3. Save with garbage collection, deflate and optional sanitize/metadata
     removal for extra savings.
"""

from __future__ import annotations

import io
import logging
from pathlib import Path

from app.core.entities import CompressionOptions, CompressStats, PdfOptions
from app.core.ports import CompressError, Compressor

log = logging.getLogger(__name__)

try:
    import fitz  # PyMuPDF
except ImportError as exc:  # pragma: no cover
    raise ImportError("PyMuPDF is required for PDF compression") from exc

from PIL import Image

_MIN_IMAGE_AREA = 64 * 64  # skip tiny images (icons, stamps) to save time


class PdfCompressor(Compressor):
    """Compresses PDF files by re-encoding embedded images and cleaning streams."""

    def compress(
        self,
        src: str,
        dst: str,
        options: CompressionOptions,
        progress=None,
    ) -> CompressStats:
        opts = options.pdf
        if progress:
            progress(0.03, "Opening PDF…")
        try:
            doc = fitz.open(src)
        except Exception as exc:
            raise CompressError(f"Cannot open PDF: {exc}") from exc

        try:
            if doc.needs_pass:
                raise CompressError("PDF is password protected — unlock it first")
            return self._compress_doc(doc, src, dst, opts, progress)
        finally:
            doc.close()

    # ------------------------------------------------------------------ #
    def _compress_doc(self, doc, src: str, dst: str, opts: PdfOptions, progress):
        original_size = _file_size(src)
        xrefs: list[int] = []
        for page in doc:
            for img in page.get_images(full=True):
                xref = img[0]
                if xref not in xrefs:
                    xrefs.append(xref)

        total = max(len(xrefs), 1)
        replaced = 0
        saved_bytes = 0
        for idx, xref in enumerate(xrefs):
            if progress:
                progress(0.05 + 0.85 * idx / total, f"Optimizing image {idx + 1}/{len(xrefs)}…")
            try:
                was_replaced, saved = self._recompress_image(doc, xref, opts)
            except Exception as exc:  # keep going on per-image failures
                log.warning("Image xref %s failed: %s", xref, exc)
                continue
            if was_replaced:
                replaced += 1
                saved_bytes += saved

        if progress:
            progress(0.92, "Cleaning document…")
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        try:
            doc.save(
                dst,
                garbage=opts.garbage,
                deflate=opts.deflate,
                clean=opts.garbage >= 4,
            )
        except Exception as exc:
            raise CompressError(f"Failed to save compressed PDF: {exc}") from exc

        if opts.remove_metadata:
            try:
                doc.set_metadata({})
            except Exception:
                pass

        compressed_size = _file_size(dst)
        log.info("PDF %s: %d images replaced, %d bytes saved", src, replaced, saved_bytes)
        return CompressStats(dst, original_size, compressed_size)

    # ------------------------------------------------------------------ #
    def _recompress_image(self, doc, xref: int, opts: PdfOptions) -> tuple[bool, int]:
        """Re-encode one embedded image. Returns (was_replaced, bytes_saved)."""
        info = doc.extract_image(xref)
        raw = info["image"]
        old_size = len(raw)

        try:
            image = Image.open(io.BytesIO(raw))
            image.load()
        except Exception:
            return False, 0

        # Downscale when the effective DPI exceeds the target.
        try:
            rects = None
            for page in doc:
                r = page.get_image_rects(xref)
                if r:
                    rects = r
                    break
            if rects:
                rect = rects[0]
                disp_w = max(rect.width, 0.01)
                dpi = image.width * 72.0 / disp_w
                if dpi > opts.max_image_dpi > 0:
                    scale = opts.max_image_dpi / dpi
                    new_w = max(1, int(image.width * scale))
                    new_h = max(1, int(image.height * scale))
                    image = image.resize((new_w, new_h), Image.LANCZOS)
        except Exception:
            pass  # downscaling is best-effort

        # Convert to RGB for JPEG encoding (handles CMYK, grayscale, palette).
        has_alpha = "A" in image.getbands()
        if has_alpha:
            background = Image.new("RGB", image.size, (255, 255, 255))
            background.paste(image, mask=image.getchannel("A"))
            image = background
        elif image.mode not in ("RGB", "L"):
            image = image.convert("RGB")

        buf = io.BytesIO()
        image.save(buf, "JPEG", quality=opts.image_quality, optimize=True, progressive=True)
        new_data = buf.getvalue()

        if len(new_data) >= old_size:
            return False, 0

        # Only touch pages that actually reference this xref.
        for page in doc:
            if any(img[0] == xref for img in page.get_images(full=True)):
                page.replace_image(xref, stream=new_data)
        return True, old_size - len(new_data)


def _file_size(path: str) -> int:
    import os

    try:
        return os.path.getsize(path)
    except OSError:
        return 0
