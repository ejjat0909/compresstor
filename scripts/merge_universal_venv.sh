#!/usr/bin/env bash
# merge_universal_venv.sh — turn the (arm64-only Homebrew) .venv into a
# universal2 build environment by lipo-merging the x86_64 wheel binaries.
#
# WHY: PyMuPDF and Pillow wheels are per-architecture. PyInstaller can only
# build a universal2 sidecar if EVERY collected Mach-O (pymupdf + PIL + the
# Python stdlib extensions) is fat. The Homebrew venv is arm64-only, so we:
#   1. download the matching x86_64 wheels,
#   2. `lipo -create` each arm64 .so with its x86_64 twin (fat binary),
#   3. replace the arm64 files in the venv site-packages.
#
# STDLIB REQUIREMENT (the remaining gotcha): PyInstaller pulls Python's
# lib-dynload extensions from sys.base_prefix — Homebrew's are arm64-only.
# Build with a python.org universal2 Python 3.11 instead (its stdlib is
# already fat), OR run PyInstaller with a venv created from one:
#
#   /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 -m venv .venv-u
#   .venv-u/bin/pip install -r requirements.txt pyinstaller
#   bash scripts/merge_universal_venv.sh .venv-u
#   COMPRESSTOR_ARCH=universal2 .venv-u/bin/python -m PyInstaller packaging/engine.spec --noconfirm
#
# Usage:  bash scripts/merge_universal_venv.sh [venv-path]   (default: .venv)
set -euo pipefail
cd "$(dirname "$0")/.."

VENV="${1:-.venv}"
PY="$VENV/bin/python"
[ -x "$PY" ] || { echo "No $PY — pass a venv path or create one first"; exit 1; }

PYVER=$("$PY" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PIP="$VENV/bin/pip"
TMP=$(mktemp -d /tmp/univ-merge-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

echo "==> Python $PYVER at $VENV"
echo "==> Downloading x86_64 wheels…"
"$PIP" download --no-deps --only-binary=:all: \
  --platform macosx_11_0_x86_64 \
  --python-version "$PYVER" --implementation cp \
  --abi "cp$PYVER" --abi abi3 \
  --dest "$TMP" PyMuPDF Pillow

echo "==> Lipo-merging per-arch Mach-O files into $VENV…"
SP=$("$PY" -c "import site; print(site.getsitepackages()[0])")
MERGED=0
for wheel in "$TMP"/*.whl; do
  unzip -q -o "$wheel" -d "$TMP/wheel"
done
# Iterate over every Mach-O inside the extracted wheels; merge into the venv
# copy when the same relative path exists there.
while IFS= read -r rel; do
  src="$TMP/wheel/$rel"
  dst="$SP/$rel"
  if [ -f "$dst" ] && file "$src" | grep -q "Mach-O"; then
    lipo -create -output "$dst.tmp" "$src" "$dst"
    mv "$dst.tmp" "$dst"
    codesign --force --sign - "$dst" 2>/dev/null || true
    MERGED=$((MERGED + 1))
    echo "  merged $rel"
  fi
done < <(cd "$TMP/wheel" && find pymupdf PIL -type f \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null || true)

echo "==> Merged $MERGED binaries."
if [ "$MERGED" -eq 0 ]; then
  echo "WARN: nothing merged — check wheel layout (PyMuPDF moved pymupdf/)." >&2
  exit 1
fi
echo "==> Verify a sample:"
"$SP" 2>/dev/null || true
file "$SP"/pymupdf/_mupdf.so | head -1
file "$SP"/PIL/_imaging*.so 2>/dev/null | head -1
echo "==> Done. Now build with:"
echo "    COMPRESSTOR_ARCH=universal2 $PY -m PyInstaller packaging/engine.spec --noconfirm"
echo "    (the venv must come from a python.org universal2 Python — see script header)"
