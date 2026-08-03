#!/usr/bin/env bash
# Build the Compresstor macOS app bundle and copy it into release/MacOS/.
# Run from the repo root:  ./scripts/build_macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PY=.venv/bin/python
[ -x "$PY" ] || { echo "No .venv found — run: $PY -m venv .venv && .venv/bin/pip install -r requirements.txt"; exit 1; }

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

echo "==> Building Compresstor.app (macOS >= 12.0)…"
ARCH_FLAG=""
if [ "$(uname -m)" = "arm64" ]; then
  # Universal2 so the app runs on both Apple Silicon and Intel Macs.
  export COMPRESSTOR_ARCH="${COMPRESSTOR_ARCH:-universal2}"
  echo "    target: universal2 (arm64 + x86_64)"
else
  echo "    target: x86_64"
fi

$PY -m PyInstaller packaging/compresstor.spec --noconfirm

echo "==> Copying bundle to release/MacOS/…"
rm -rf release/MacOS/Compresstor.app
mkdir -p release/MacOS
cp -R dist/Compresstor.app release/MacOS/
rm -rf build dist

echo "==> Done."
ls -lh release/MacOS/Compresstor.app/Contents/MacOS/Compresstor
echo "Artifact: release/MacOS/Compresstor.app"
