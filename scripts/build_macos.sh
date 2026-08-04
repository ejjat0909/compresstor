#!/usr/bin/env bash
# Two-stage macOS release build (Phase 6 — Flutter frontend + Python engine).
#
#   Stage 1  engine sidecar  : PyInstaller packaging/engine.spec -> dist/engine_cli/
#   Stage 2  Flutter app     : flutter build macos --release -> compresstor.app
#   Stage 3  bundle          : copy sidecar into <app>/Contents/Resources/engine/
#             + re-sign (ad-hoc, deep) and install to release/MacOS/Compresstor.app
#
# Run from the repo root:  ./scripts/build_macos.sh [--universal] [--dmg]
#
# Notes:
#   - The Flutter .app builds for the HOST arch (arm64 here). A universal2
#     engine additionally requires a lipo-merged universal venv (see
#     docs/stack-migration-plan-flutter.md Phase 6) — pass COMPRESSTOR_ARCH=universal2.
#   - Never copy a fresh .app over an existing release bundle: taskgated kills
#     the merged bundle. We rm the old one first (below).
set -euo pipefail
cd "$(dirname "$0")/.."

# Fresh-machine bootstrap: locate a Python >= 3.10 and create the venv.
find_python3() {
  for c in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$c" >/dev/null 2>&1 &&
       "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

PY=.venv/bin/python
if [ ! -x "$PY" ]; then
  PY3=$(find_python3) || {
    echo "No Python >= 3.10 found. Install a recent Python 3 "
    echo "(https://www.python.org/downloads/ or brew install python@3.12) and retry."
    exit 1
  }
  echo "==> Bootstrapping .venv with $PY3…"
  "$PY3" -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -r requirements.txt pyinstaller
fi
command -v flutter >/dev/null || {
  echo "flutter not on PATH — install from https://docs.flutter.dev/get-started/install (macOS: Xcode + CocoaPods required)"
  exit 1
}

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

# Single version source: repo-root version.json (docs/update-plan.md).
VER=$("$PY" -c "import json;print(json.load(open('version.json'))['version'])")
BUILD=$("$PY" -c "import json;print(json.load(open('version.json'))['build'])")
echo "==> Version from version.json: $VER (build $BUILD)"
cp version.json flutter/assets/version.json  # keep the bundled asset in sync

MAKE_DMG=0
ARCH="${COMPRESSTOR_ARCH:-arm64}"
for arg in "$@"; do
  case "$arg" in
    --universal) ARCH="universal2" ;;
    --dmg) MAKE_DMG=1 ;;
  esac
done

if [ "$ARCH" = "universal2" ]; then
  echo "==> universal2 engine - requires a lipo-merged universal venv (see docs)."
fi

echo "==> Stage 1: engine sidecar (PyInstaller, $ARCH)…"
COMPRESSTOR_ARCH="$ARCH" "$PY" -m PyInstaller packaging/engine.spec \
  --noconfirm --distpath dist --workpath build
test -x dist/engine_cli/engine_cli || { echo "Sidecar build failed"; exit 1; }

echo "==> Stage 2: Flutter release app…"
( cd flutter && flutter build macos --release --build-name "$VER" --build-number "$BUILD" )

APP=flutter/build/macos/Build/Products/Release/compresstor.app
test -d "$APP" || { echo "Flutter app not produced"; exit 1; }

echo "==> Stage 3: bundle engine sidecar into Resources/engine/…"
rm -rf "$APP/Contents/Resources/engine"
mkdir -p "$APP/Contents/Resources/engine"
cp -R dist/engine_cli/. "$APP/Contents/Resources/engine/"
test -x "$APP/Contents/Resources/engine/engine_cli"
cp version.json "$APP/Contents/Resources/version.json"

echo "==> Re-signing app bundle (ad-hoc, deep)…"
codesign --force --deep --sign - "$APP" || echo "WARN: codesign --deep failed"
codesign --verify --deep --strict "$APP" || echo "WARN: codesign --verify reported issues"

echo "==> Installing to release/MacOS/Compresstor.app (rm old first — taskgated rule)…"
rm -rf release/MacOS/Compresstor.app
mkdir -p release/MacOS
cp -R "$APP" release/MacOS/Compresstor.app

echo "==> Update artifact: Compresstor-$VER-macos.zip + sha256…"
ZIP="release/Compresstor-$VER-macos.zip"
ditto -c -k --keepParent release/MacOS/Compresstor.app "$ZIP"
printf '%s  %s\n' "$(shasum -a 256 "$ZIP" | awk '{print $1}')" "$(basename "$ZIP")" \
  > "release/Compresstor-$VER.sha256"
ls -lh "$ZIP" "release/Compresstor-$VER.sha256"

echo "==> Cleanup build artifacts…"
rm -rf build dist

echo "==> Done."
ls -lh release/MacOS/Compresstor.app/Contents/MacOS/compresstor
ls -lh release/MacOS/Compresstor.app/Contents/Resources/engine/engine_cli
echo "Artifact: release/MacOS/Compresstor.app"

if [ "$MAKE_DMG" = "1" ]; then
  echo "==> Building DMG…"
  bash scripts/build_dmg.sh
fi