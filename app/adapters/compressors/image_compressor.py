"""Image compression adapter using Pillow.

Handles JPEG, PNG, WebP, TIFF, BMP and GIF. Format conversion (PNG -> JPEG/
WebP) is applied when *preserve_format* is disabled or the source format has
no meaningful lossy options (BMP).
"""

from __future__ import annotations

import io
import logging
from pathlib import Path

from PIL import Image, ImageOps

from app.core.entities import CompressionOptions, CompressStats, ImageOptions
from app.core.ports import CompressError, Compressor

log = logging.getLogger(__name__)

# Map quality slider -> palette colours for PNG quantization.
_PNG_COLORS = {90: 256, 80: 256, 70: 192, 60: 128, 50: 96, 40: 64, 30: 48}


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

        # Downscale when requested.
        if opts.resize_max and opts.resize_max > 0:
            max_dim = max(im.size)
            if max_dim > opts.resize_max:
                scale = opts.resize_max / max_dim
                im = im.resize(
                    (max(1, int(im.width * scale)), max(1, int(im.height * scale))),
                    Image.LANCZOS,
                )

        fmt = self._target_format(src, im, opts)
        out_path = self._with_extension(dst, fmt)
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        if progress:
            progress(0.35, f"Encoding {fmt.upper()}…")

        exif = None if opts.strip_metadata else im.info.get("exif")

        try:
            if fmt == "JPEG":
                self._save_jpeg(im, out_path, opts, exif)
            elif fmt == "WEBP":
                self._save_webp(im, out_path, opts, exif)
            elif fmt == "PNG":
                self._save_png(im, out_path, opts)
            elif fmt == "TIFF":
                im.save(out_path, "TIFF", compression="tiff_lzw")
            elif fmt == "GIF":
                im.convert("P", palette=Image.ADAPTIVE).save(out_path, "GIF", optimize=True)
            else:
                im.save(out_path, fmt)
        except Exception as exc:
            raise CompressError(f"Failed to encode image: {exc}") from exc

        if progress:
            progress(0.98, "Finalizing…")
        return CompressStats(out_path, original_size, Path(out_path).stat().st_size)

    # ------------------------------------------------------------------ #
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
