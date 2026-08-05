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

from app.adapters.compressors.target import compress_to_target
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
            if options.target_bytes is None:
                return self._compress_doc(doc, src, dst, opts, opts.image_quality, opts.max_image_dpi, progress)

            # Max-size target: re-encode the document at progressively lower
            # image quality AND lower DPI until the output fits the budget.
            # Quality alone tops out around 20; without DPI reduction, scan-heavy
            # PDFs can't reach small budgets. Each step cascades both knobs.
            original_size = _file_size(src)
            base_q = opts.image_quality
            base_dpi = opts.max_image_dpi if opts.max_image_dpi > 0 else 144
            steps = [
                (base_q, base_dpi),
                (min(base_q, 60), min(base_dpi, 120)),
                (45, min(base_dpi, 100)),
                (35, 84),
                (28, 72),
                (22, 60),
                (18, 48),
            ]

            def run_step(step, tmp: str) -> CompressStats:
                quality, dpi = step
                # Per-image progress is suppressed on ladder passes; the
                # ladder runner reports overall progress instead.
                return self._compress_doc(doc, src, tmp, opts, quality, dpi, None)

            stats = compress_to_target(
                run_step,
                dst,
                options.target_bytes,
                steps,
                progress=progress,
                progress_start=0.03,
                progress_span=0.55,
                label="Optimizing PDF",
            )

            # If the image-optimization ladder couldn't hit the budget (common
            # for text/vector PDFs with no embedded raster images), fall back
            # to rasterizing every page at progressively lower DPI. This is
            # lossy for text but is the only way to reach small budgets on
            # long text PDFs.
            if _file_size(dst) > options.target_bytes:
                image_ladder_size = _file_size(dst)
                # Preserve the image-ladder output so the raster ladder can't
                # clobber it with a larger result.
                backup = str(Path(dst).with_name(f"{Path(dst).stem}.imgbest{Path(dst).suffix}"))
                Path(dst).replace(backup)

                raster_steps = [110, 90, 72, 60, 50, 42, 36, 30, 24]

                def raster_step(dpi_step, tmp: str) -> CompressStats:
                    return self._rasterize_doc(doc, src, tmp, dpi_step, opts, quality=55)

                try:
                    stats = compress_to_target(
                        raster_step,
                        dst,
                        options.target_bytes,
                        raster_steps,
                        progress=progress,
                        progress_start=0.58,
                        progress_span=0.4,
                        label="Rasterizing pages",
                    )
                except Exception:
                    Path(backup).replace(dst)
                    raise

                # Keep whichever ladder produced the smaller file.
                if _file_size(dst) > image_ladder_size:
                    Path(backup).replace(dst)
                    stats = CompressStats(dst, _file_size(src), image_ladder_size)
                else:
                    Path(backup).unlink(missing_ok=True)

            if _file_size(dst) > options.target_bytes:
                budget_mb = options.target_bytes / (1024 * 1024)
                final_mb = _file_size(dst) / (1024 * 1024)
                raise CompressError(
                    f"Cannot compress to {budget_mb:.2f} MB or below "
                    f"(smallest achievable: {final_mb:.2f} MB). "
                    f"Try a larger budget or a lower quality level."
                )
            return stats
        finally:
            doc.close()

    # ------------------------------------------------------------------ #
    def _compress_doc(self, doc, src: str, dst: str, opts: PdfOptions, quality: int, max_dpi: int, progress):
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
                was_replaced, saved = self._recompress_image(doc, xref, opts, quality, max_dpi)
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
    def _rasterize_doc(self, doc, src: str, dst: str, dpi: int, opts: PdfOptions, quality: int) -> CompressStats:
        """Render every page to a JPEG at *dpi*, rebuild PDF from images.

        Used as a last resort when image-optimization can't hit the target
        (e.g. long text PDFs). Text becomes non-selectable but file shrinks
        dramatically.
        """
        original_size = _file_size(src)
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        zoom = dpi / 72.0
        matrix = fitz.Matrix(zoom, zoom)
        out = fitz.open()
        try:
            for page in doc:
                pix = page.get_pixmap(matrix=matrix, alpha=False)
                buf = io.BytesIO()
                img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
                img.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
                jpeg = buf.getvalue()
                new_page = out.new_page(width=page.rect.width, height=page.rect.height)
                new_page.insert_image(new_page.rect, stream=jpeg)
            save_kwargs = dict(garbage=opts.garbage, deflate=opts.deflate, clean=opts.garbage >= 4)
            out.save(dst, **save_kwargs)
        finally:
            out.close()
        return CompressStats(dst, original_size, _file_size(dst))

    # ------------------------------------------------------------------ #
    def _recompress_image(self, doc, xref: int, opts: PdfOptions, quality: int, max_dpi: int) -> tuple[bool, int]:
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
                if dpi > max_dpi > 0:
                    scale = max_dpi / dpi
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
        image.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
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
