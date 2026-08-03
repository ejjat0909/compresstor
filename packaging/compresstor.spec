# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for Compresstor.

Builds a platform-appropriate bundle:
  macOS  -> Compresstor.app (windowed, deployment target >= 12.0)
  Windows-> Compresstor/ directory with Compresstor.exe (windowed)

Usage:
  pyinstaller packaging/compresstor.spec --noconfirm
"""

import os
import platform
import sys
from pathlib import Path

# The spec is always invoked from the repo root (see build scripts).
ROOT = Path.cwd()

# macOS: universal2 by default on Apple Silicon (also covers Intel Macs).
# Override with COMPRESSTOR_ARCH (x86_64 | arm64 | universal2).
TARGET_ARCH = os.environ.get("COMPRESSTOR_ARCH")
if TARGET_ARCH is None and sys.platform == "darwin":
    TARGET_ARCH = "universal2" if platform.machine() == "arm64" else "x86_64"

datas = [
    (str(ROOT / "assets" / "icons"), "assets/icons"),
    (str(ROOT / "assets" / "fonts"), "assets/fonts"),
    (str(ROOT / "assets" / "icon"), "assets/icon"),
]

a = Analysis(
    [str(ROOT / "main.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # PIL.Image conditionally imports numpy (fromarray integration) which we
    # never use; excluding keeps the bundle lean and avoids arch-merging it.
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
        name="Compresstor",
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=False,
        console=False,
        target_arch=TARGET_ARCH,
    )
    coll = COLLECT(
        exe,
        a.binaries,
        a.datas,
        strip=False,
        upx=False,
        name="Compresstor",
    )
    app = BUNDLE(
        coll,
        name="Compresstor.app",
        icon=str(ROOT / "assets" / "icon" / "Compresstor.icns"),
        bundle_identifier="com.compresstor.desktop",
        info_plist={
            "CFBundleName": "Compresstor",
            "CFBundleDisplayName": "Compresstor",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1.0.0",
            "NSHighResolutionCapable": True,
            "LSMinimumSystemVersion": "12.0",
            "NSHumanReadableCopyright": "© 2026 Compresstor",
            "NSPrincipalClass": "NSApplication",
            "NSSupportsAutomaticGraphicsSwitching": True,
        },
    )
else:
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.datas,
        [],
        name="Compresstor",
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=False,
        console=False,
        icon=str(ROOT / "assets" / "icon" / "Compresstor.ico"),
        version=None,
    )
    coll = None
    app = None
