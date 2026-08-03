# Compresstor

**Compress PDF and image files — fast, private and fully local.**

Compresstor is a premium desktop app (PySide6 / Qt) that shrinks PDF and
image files without uploading them anywhere. Its interface follows the
visual language of Filament, shadcn/ui and Tailwind CSS: clean cards, a
collapsible sidebar, dark mode, toast notifications and subtle animations.

![stack](https://img.shields.io/badge/Python-3.11-blue) ![qt](https://img.shields.io/badge/PySide6-6.8-green)

## Features

- **PDF compression** — re-encodes embedded images (JPEG quality + DPI
  scaling), garbage-collects dead objects, deflates streams, strips metadata.
  Typical savings: 60–95%.
- **Image compression** — JPEG/WebP quality control, PNG palette
  quantization, resizing, metadata stripping, BMP→PNG and format conversion.
- **Presets** — High / Balanced / Maximum, plus an advanced panel with
  sliders for PDF quality, max DPI, image quality and max dimension.
- **Max size target** — set a size in MB and the output is compressed to
  that size or below (iterative quality/resolution ladder; errors when the
  target is not smaller than the original file).
- **Output modes** — new file next to the original, chosen folder, or
  replace in place (with confirmation).
- **Filament-style table** — sorting, search, filtering, pagination,
  multi-select, right-click context menu, status badges.
- **History** — every job is stored locally with savings statistics.
- **Theming** — dark-only interface, 8 accent colors or a custom picker,
  Inter typography, 8px spacing system.
- **Fully offline** — your files never leave the device.

## Requirements

- Python 3.11 (3.9+ works for dev)
- macOS 12 or newer, Windows 10 21H2+ (build/run)
- Runtime binary for macOS 12+ / Windows 10+ (see release/)

## Development

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python main.py            # run the app
.venv/bin/python -m pytest tests/   # run the test suite
```

### Visual QA

```bash
QT_QPA_PLATFORM=offscreen .venv/bin/python scripts/qa_screenshot.py /tmp/qa
# renders every page in both themes + runs a real compression; PNGs in /tmp/qa
```

## Architecture

Clean architecture with a framework-free core:

```
main.py                      composition root
app/core/                    entities, ports (interfaces), use cases — no Qt
app/adapters/                compressors (PyMuPDF, Pillow) + JSON stores
app/presentation/            Qt UI: theme engine, component library, pages
   theme/                    palette, QSS generator, fonts, theme manager
   components/               buttons, cards, toasts, table, modal, ...
   pages/                    one file per page (dashboard, history, settings)
scripts/                     build scripts + QA harness
packaging/                   PyInstaller spec
release/                     built artifacts (macOS / Windows)
```

Dependency rule: `presentation -> adapters -> core`. The core layer has no
Qt imports and is fully unit-tested.

## Building releases

macOS (build on a Mac, produces a universal2 .app for Intel + Apple Silicon):

```bash
./scripts/build_macos.sh
```

Windows (run on Windows 10/11):

```
scripts\build_windows.bat
```

Artifacts land in `release/MacOS/` and `release/Windows/`.

> The macOS bundle is unsigned, so first launch requires
> right-click → Open (or System Settings → Privacy & Security → Open Anyway).

## License

MIT
