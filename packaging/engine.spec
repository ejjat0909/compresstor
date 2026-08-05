# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the Compresstor engine sidecar (Flutter migration).

Builds the Python compression engine (PyMuPDF + Pillow) as a standalone
executable — deliberately NO Qt (the old main.py/PySide6 bundle is replaced by
a Flutter UI that spawns this sidecar). One-folder build:

    ./dist/engine_cli/
        engine_cli                  (macOS) / engine_cli.exe (Windows)
        _internal/...               (bundled Python + engine deps)

Invoked by EngineClient as `engine_cli <subcommand>` (see docs/engine-protocol.md).
The app bundle copies dist/engine_cli into <app>/Contents/Resources/engine/
(Windows: <exe_dir>\\engine\\).

Arch: host-native by default. On macOS, override with COMPRESSTOR_ARCH
(arm64 | x86_64 | universal2). A true universal2 build additionally requires a
lipo-merged universal venv (documented in docs/stack-migration-plan-flutter.md
Phase 6); on an arm64-only HH then dev venv this spec should be run with
COMPRESSTOR_ARCH=arm64.

Usage (from the repo root):
    COMPRESSTOR_ARCH=arm64 .venv/bin/python -m PyInstaller packaging/engine.spec --noconfirm
"""

import os
import platform
import sys
from pathlib import Path

ROOT = Path.cwd()

TARGET_ARCH = os.environ.get("COMPRESSTOR_ARCH")
if TARGET_ARCH is None and sys.platform == "darwin":
    TARGET_ARCH = "arm64" if platform.machine() == "arm64" else "x86_64"

a = Analysis(
    [str(ROOT / "app" / "engine" / "engine_cli.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[],
    hiddenimports=[
        # Engine domain + adapters (the CLI imports them lazily/hot).
        "app.core.entities",
        "app.core.ports",
        "app.core.use_cases",
        "app.adapters.compressors.registry",
        "app.adapters.compressors.pdf_compressor",
        "app.adapters.compressors.image_compressor",
        "app.adapters.compressors.target",
        "app.adapters.storage.json_stores",
        # PyMuPDF + Pillow are imported lazily; modulegraph reaches them via
        # registry.py, but list them explicitly to be safe.
        "fitz",
        "PIL",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # PIL.Image conditionally imports numpy (fromarray); we never use it —
    # excluding keeps the bundle lean and avoids arch-merging a heavy dep.
    excludes=["numpy"],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

if sys.platform == "darwin":
    exe = EXE(
        pyz,
        a.scripts,
        [],
        exclude_binaries=True,
        name="engine_cli",
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=False,
        console=True,  # CLI sidecar: stdout carries JSON-lines events.
        target_arch=TARGET_ARCH,
    )
    coll = COLLECT(
        exe,
        a.binaries,
        a.datas,
        strip=False,
        upx=False,
        name="engine_cli",
    )
else:
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.datas,
        [],
        name="engine_cli",
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=False,
        console=True,
        icon=str(ROOT / 'assets' / 'icon' / 'Compresstor.ico'),
        version=None,
    )
    coll = None