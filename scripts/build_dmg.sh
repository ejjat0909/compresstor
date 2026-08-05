#!/usr/bin/env bash
# build_dmg.sh — package the macOS universal2 release into a polished .dmg.
#
# Uses create-dmg for reliable background image and icon positioning.
# Requires the built .app first:  scripts/build_macos.sh
#
# Usage:  bash scripts/build_dmg.sh [version]
# Output: release/MacOS/Compresstor-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.0}"
APP="$ROOT/release/MacOS/Compresstor.app"
FINAL="$ROOT/release/MacOS/Compresstor-$VERSION.dmg"
BG="$ROOT/build/dmg-background.png"

log() { printf '\033[1;34m== %s\033[0m\n' "$*"; }

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found — build the app first" >&2
  exit 1
fi
if ! command -v create-dmg >/dev/null; then
  echo "ERROR: create-dmg not found — install with: brew install create-dmg" >&2
  exit 1
fi

mkdir -p "$ROOT/build" "$ROOT/release/MacOS"

log "rendering DMG background"
"$ROOT/.venv/bin/python" "$ROOT/scripts/build_dmg_background.py" "$BG" --version "$VERSION"

rm -f "$FINAL"

log "building DMG with create-dmg"

# Copy installer script next to the app for inclusion in DMG
cp "$ROOT/scripts/Install Compresstor.command" "$ROOT/release/MacOS/Install Compresstor.command"
chmod +x "$ROOT/release/MacOS/Install Compresstor.command"

create-dmg \
  --volname "Compresstor $VERSION" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 96 \
  --icon "Compresstor.app" 180 200 \
  --app-drop-link 480 200 \
  --no-internet-enable \
  --hide-extension "Compresstor.app" \
  --add-file "Install Compresstor.command" "$ROOT/release/MacOS/Install Compresstor.command" 330 340 \
  "$FINAL" \
  "$APP"

rm -f "$ROOT/release/MacOS/Install Compresstor.command"

SIZE="$(du -h "$FINAL" | awk '{print $1}')"
log "done: $FINAL ($SIZE)"
