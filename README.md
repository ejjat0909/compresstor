# Compresstor

**Compress PDF and image files — fast, private and fully local.**

Compresstor is a premium desktop app (Flutter frontend + Python compression
engine) that shrinks PDF and image files without uploading them anywhere. Its
interface follows the visual language of Filament, shadcn/ui and Tailwind CSS:
clean cards, a collapsible sidebar, dark mode, toast notifications and subtle
animations. The engine (PyMuPDF + Pillow) runs as a bundled sidecar process.

![stack](https://img.shields.io/badge/Flutter-3.44-blue) ![engine](https://img.shields.io/badge/Python-3.11-green)

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

The app is a Flutter desktop frontend (`flutter/`) talking JSON-lines over
stdin/stdout to the Python engine (`app/engine/engine_cli.py`, per
`docs/engine-protocol.md`). In development the engine runs from the repo venv:

```bash
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install pyinstaller        # only needed for release builds

cd flutter && flutter pub get && flutter run          # app + engine (dev)
cd flutter && flutter test                             # 64 Dart tests
.venv/bin/python -m pytest tests/                     # 38 engine tests
cd flutter && flutter test integration_test/compression_flow_test.dart -d macos
#                                                       real engine through the UI
```

## Architecture

Two layers, one protocol (`docs/engine-protocol.md`):

```
flutter/                     Flutter UI: shell, pages, theme, state
   lib/engine/               EngineClient (spawns engine_cli, parses JSON-lines)
app/engine/engine_cli.py     engine entry point — one subcommand per process
app/core/                    entities, ports (interfaces), use cases — no Qt
app/adapters/                compressors (PyMuPDF, Pillow) + JSON stores
scripts/                     build scripts + QA harness (parity, engine QA)
packaging/                   PyInstaller spec (engine sidecar only)
release/                     built artifacts (macOS / Windows)
```

Dependency rule: `adapters -> core`; the core layer is framework-free and
fully unit-tested. The Flutter side stays thin — all compression logic lives
in the Python engine, so old/new app outputs are byte-for-byte identical for
deterministic formats (`scripts/parity_check.py`).

## Building releases

Two-stage: the engine sidecar is built with PyInstaller (no Qt), then the
Flutter app is built and the sidecar is bundled into the app's Resources
(`Contents/Resources/engine/` on macOS; `engine\` next to the exe on Windows).
`EngineClient` auto-detects the bundled engine at runtime and falls back to
the dev venv in development.

macOS (build on a Mac):

```bash
./scripts/build_macos.sh                 # stage 1+2+3: sidecar, app, bundle, sign
bash scripts/build_dmg.sh                # optional: package the .app into a .dmg
```

Windows (run on Windows 10/11):

```
scripts\build_windows.bat
```

Artifacts land in `release/MacOS/Compresstor.app` (and `.dmg`) and
`release/Windows/Compresstor\`.

Architecture notes:
- The Flutter `.app` is a universal2 binary (Xcode builds both archs), but the
  engine sidecar is built for the HOST arch by default (arm64 here). A
  universal2 engine needs a lipo-merged universal venv — see
  `scripts/merge_universal_venv.sh` and `docs/stack-migration-plan-flutter.md`.
- The app is NOT sandboxed (the sidecar needs unrestricted file access; v1.0.0
  shipped the same way) and is ad-hoc signed, so first launch requires
  right-click → Open (or System Settings → Privacy & Security → Open Anyway).

## License

MIT
