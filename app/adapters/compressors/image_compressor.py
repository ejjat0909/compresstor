"""Image compression adapter using Pillow.

Handles JPEG, PNG, WebP, TIFF, BMP and GIF. Format conversion (PNG -> JPEG/
WebP) is applied when *preserve_format* is disabled or the source format has
no meaningful lossy options (BMP).

When a max-size target is set (``CompressionOptions.max_size_mb``) the
encoder runs a *quality ladder*: progressively lower quality / resolution
until the output fits the budget, keeping the smallest candidate overall.
"""

from __future__ import annotations

import io
import logging
from dataclasses import replace
from pathlib import Path

from PIL import Image, ImageOps

from app.adapters.compressors.target import compress_to_target
from app.core.entities import CompressionOptions, CompressStats, ImageOptions
from app.core.ports import CompressError, Compressor

log = logging.getLogger(__name__)

# Map quality slider -> palette colours for PNG quantization.
_PNG_COLORS = {90: 256, 80: 256, 70: 192, 60: 128, 50: 96, 40: 64, 30: 48}

#: (quality, dimension factor) ladder used to chase a max-size target.
_JPEG_WEBP_LADDER = [(0, 1.0), (65, 0.90), (50, 0.82), (40, 0.75), (30, 0.68), (22, 0.62)]
_PNG_LADDER = [(0, 1.0), (60, 0.90), (50, 0.82), (40, 0.75), (30, 0.68)]


class ImageCompressor(Compressor):
    """Compresses raster images with Pillow."""

    def compress(
        self,
        src: str,
        dst: str,
        options: CompressionOptions,
        progress=None,
    ) -> CompressStats:
        opts = options.image
        original_size = Path(src).stat().st_size
        if progress:
            progress(0.05, "Reading image…")

        try:
            with Image.open(src) as im:
                im = ImageOps.exif_transpose(im)
                im.load()
                # Convert palette images for consistent handling.
                if im.mode == "P":
                    im = im.convert("RGBA" if "transparency" in im.info else "RGB")
        except Exception as exc:
            raise CompressError(f"Cannot read image: {exc}") from exc

        if progress:
            progress(0.2, "Processing…")

        fmt = self._target_format(src, im, opts)
        out_path = self._with_extension(dst, fmt)
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        exif = None if opts.strip_metadata else im.info.get("exif")

        # Formats without a quality knob (TIFF/GIF/…) or no target: single pass.
        if fmt not in ("JPEG", "WEBP", "PNG") or options.target_bytes is None:
            if progress:
                progress(0.35, f"Encoding {fmt.upper()}…")
            img = self._apply_resize(im, opts)
            try:
                self._encode(img, out_path, opts, exif)
            except Exception as exc:
                raise CompressError(f"Failed to encode image: {exc}") from exc
            if progress:
                progress(0.98, "Finalizing…")
            return CompressStats(out_path, original_size, Path(out_path).stat().st_size)

        # ---- target-size ladder ---------------------------------------- #
        ladder = _PNG_LADDER if fmt == "PNG" else _JPEG_WEBP_LADDER
        # Never step UP in quality: later passes stay <= the configured one.
        steps = [(min(q, opts.quality), factor) for q, factor in ladder]
        steps[0] = (opts.quality, 1.0)
        base_max_dim = max(im.size)
        step0_dim = self._target_dim(base_max_dim, opts.resize_max)

        def run_step(step, tmp: str) -> CompressStats:
            quality, factor = step
            dim = step0_dim
            if factor < 1.0:
                dim = min(step0_dim, int(base_max_dim * factor))
            img = im
            if dim and dim < max(img.size):
                scale = dim / max(img.size)
                img = im.resize(
                    (max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                    Image.LANCZOS,
                )
            opts_q = replace(opts, quality=quality)
            try:
                self._encode(img, tmp, opts_q, exif)
            except Exception as exc:
                raise CompressError(f"Failed to encode image: {exc}") from exc
            return CompressStats(tmp, original_size, Path(tmp).stat().st_size)

        stats = compress_to_target(
            run_step,
            out_path,
            options.target_bytes,
            steps,
            progress=progress,
            progress_start=0.35,
            progress_span=0.6,
            label=f"Encoding {fmt.upper()}",
        )
        if progress:
            progress(0.98, "Finalizing…")
        return stats

    # ------------------------------------------------------------------ #
    @staticmethod
    def _apply_resize(im: Image.Image, opts: ImageOptions) -> Image.Image:
        """Downscale *im* when *resize_max* is set and exceeded."""
        if opts.resize_max and opts.resize_max > 0:
            max_dim = max(im.size)
            if max_dim > opts.resize_max:
                scale = opts.resize_max / max_dim
                return im.resize(
                    (max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                    Image.LANCZOS,
                )
        return im

    @staticmethod
    def _target_dim(base_max: int, resize_max: int) -> int:
        """Largest allowed dimension for the first ladder step."""
        if resize_max and resize_max > 0:
            return min(base_max, resize_max)
        return base_max

    @staticmethod
    def _encode(im: Image.Image, path: str, opts: ImageOptions, exif) -> None:
        """Encode *im* to *path* with the given options (one format)."""
        fmt = (Path(path).suffix[1:] or "jpeg").upper()
        if fmt == "JPG":
            fmt = "JPEG"
        if fmt == "JPEG":
            ImageCompressor._save_jpeg(im, path, opts, exif)
        elif fmt == "WEBP":
            ImageCompressor._save_webp(im, path, opts, exif)
        elif fmt == "PNG":
            ImageCompressor._save_png(im, path, opts)
        elif fmt == "TIFF":
            im.save(path, "TIFF", compression="tiff_lzw")
        elif fmt == "GIF":
            im.convert("P", palette=Image.ADAPTIVE).save(path, "GIF", optimize=True)
        else:
            im.save(path, fmt)

    @staticmethod
    def _target_format(src: str, im: Image.Image, opts: ImageOptions) -> str:
        fmt = (Path(src).suffix[1:] or "jpeg").upper()
        if fmt == "JPG":
            fmt = "JPEG"
        if opts.preserve_format:
            return "PNG" if fmt == "BMP" else fmt  # BMP always converts to PNG
        # Conversion requested: honour transparency with WebP, else JPEG.
        has_alpha = "A" in im.getbands()
        return "WEBP" if has_alpha else "JPEG"

    @staticmethod
    def _with_extension(dst: str, fmt: str) -> str:
        ext = {  # noqa: C901
            "JPEG": ".jpg",
            "WEBP": ".webp",
            "PNG": ".png",
            "TIFF": ".tiff",
            "GIF": ".gif",
        }.get(fmt, f".{fmt.lower()}")
        p = Path(dst)
        return str(p.with_suffix(ext))

    @staticmethod
    def _save_jpeg(im: Image.Image, path: str, opts: ImageOptions, exif) -> None:
        img = im
        if "A" in im.getbands():
            bg = Image.new("RGB", im.size, (255, 255, 255))
            bg.paste(im, mask=im.getchannel("A"))
            img = bg
        elif im.mode not in ("RGB", "L"):
            img = im.convert("RGB")
        kwargs = dict(
            quality=opts.quality,
            optimize=True,
            progressive=True,
            subsampling=2 if opts.quality <= 75 else 0,
        )
        if exif is not None:  # Pillow >= 12 crashes on exif=None
            kwargs["exif"] = exif
        img.save(path, "JPEG", **kwargs)

    @staticmethod
    def _save_webp(im: Image.Image, path: str, opts: ImageOptions, exif) -> None:
        img = im.convert("RGB" if im.mode not in ("RGB", "RGBA") else im.mode)
        kwargs = dict(quality=opts.quality, method=6, exact=False)
        if exif is not None:
            kwargs["exif"] = exif
        img.save(path, "WEBP", **kwargs)

    @staticmethod
    def _save_png(im: Image.Image, path: str, opts: ImageOptions) -> None:
        colors = _PNG_COLORS.get(int(round(opts.quality / 10) * 10), 256)
        if opts.quality < 85 and im.mode in ("RGB", "RGBA") and colors:
            # Pillow >= 12: only FASTOCTREE / libimagequant work on RGBA.
            method = Image.FASTOCTREE if im.mode == "RGBA" else Image.MEDIANCUT
            im = im.quantize(colors=colors, method=method, dither=Image.FLOYDSTEINBERG)
        im.save(path, "PNG", optimize=True)
