# Engine Parity Report

Same fixtures through the legacy engine path (`CompressUseCase`
directly) vs the new engine CLI (`engine_cli.py compress`, as the
Flutter app spawns it). Both paths share the same core use case +
compressors, so output SIZES must be identical for every file.
Byte comparison applies only to deterministic formats; PDF and
low-quality PNG outputs are not byte-deterministic by design:
PyMuPDF stamps a fresh random document `/ID` per save, and Pillow's
PNG quantization uses a randomized Floyd–Steinberg dither.

Generated: 2026-08-04  
Command: `python scripts/parity_check.py`

| File | Level | Original (B) | Old path size (B) | New path size (B) | Status | Sizes | Bytes |
|------|-------|-------------:|------------------:|------------------:|--------|-------|-------|
| doc.pdf | high | 1,325,571 | 74,855 | 74,855 | done/done | ✅ | n/a (PDF /ID) |
| doc.pdf | balanced | 1,325,571 | 38,651 | 38,651 | done/done | ✅ | n/a (PDF /ID) |
| doc.pdf | maximum | 1,325,571 | 19,514 | 19,514 | done/done | ✅ | n/a (PDF /ID) |
| small.pdf | high | 788 | 753 | 753 | done/done | ✅ | n/a (PDF /ID) |
| small.pdf | balanced | 788 | 753 | 753 | done/done | ✅ | n/a (PDF /ID) |
| small.pdf | maximum | 788 | 753 | 753 | done/done | ✅ | n/a (PDF /ID) |
| photo.jpg | high | 1,320,586 | 279,098 | 279,098 | done/done | ✅ | ✅ |
| photo.jpg | balanced | 1,320,586 | 152,073 | 152,073 | done/done | ✅ | ✅ |
| photo.jpg | maximum | 1,320,586 | 108,853 | 108,853 | done/done | ✅ | ✅ |
| logo.png | high | 3,240 | 1,593 | 1,593 | done/done | ✅ | n/a (PNG dither) |
| logo.png | balanced | 3,240 | 1,337 | 1,337 | done/done | ✅ | n/a (PNG dither) |
| logo.png | maximum | 3,240 | 953 | 953 | done/done | ✅ | n/a (PNG dither) |

**Result: 12/12 rows identical.** Parity holds.
