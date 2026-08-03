#!/usr/bin/env bash
# build_dmg.sh — package the macOS universal2 release into a polished .dmg.
#
# Two-phase recipe: build a read-write template DMG, customize it (window
# background, icon layout via Finder when available), then convert to a
# compressed read-only UDZO image. Requires the built .app first:
#   scripts/build_macos.sh   (or the franken-venv PyInstaller build)
#
# Usage:  bash scripts/build_dmg.sh [version]
# Output: release/MacOS/Compresstor-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.0}"
APP="$ROOT/release/MacOS/Compresstor.app"
VOLNAME="Compresstor $VERSION"
TEMPLATE="$ROOT/build/Compresstor-template.dmg"
FINAL="$ROOT/release/MacOS/Compresstor-$VERSION.dmg"
STAGING="$(mktemp -d)"
BG="$ROOT/build/dmg-background.png"

log() { printf '\033[1;34m== %s\033[0m\n' "$*"; }

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found — build the app first" >&2
  exit 1
fi
if ! command -v hdiutil >/dev/null; then
  echo "ERROR: hdiutil not found — this script must run on macOS" >&2
  exit 1
fi

mkdir -p "$ROOT/build" "$ROOT/release/MacOS"

log "rendering DMG background"
"$ROOT/.venv/bin/python" "$ROOT/scripts/build_dmg_background.py" "$BG" --version "$VERSION"

log "staging app + Applications symlink"
ln -s /Applications "$STAGING/Applications"
cp -R "$APP" "$STAGING/Compresstor.app"

log "building read-write template"
rm -f "$TEMPLATE"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDRW \
  "$TEMPLATE" >/dev/null

log "mounting template for customization"
MOUNT_POINT="$(hdiutil attach "$TEMPLATE" -noverify -noautoopen -nobrowse | \
  awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
if [[ -z "$MOUNT_POINT" ]]; then
  echo "ERROR: failed to mount template" >&2
  rm -rf "$STAGING"
  exit 1
fi
echo "mounted at $MOUNT_POINT"

# background image lives in a hidden folder inside the volume
mkdir -p "$MOUNT_POINT/.background"
cp "$BG" "$MOUNT_POINT/.background/background.png"

log "arranging window (Finder layout — best effort)"
osascript <<EOF 2>/dev/null || true
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 760, 500}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png" of container window
    set position of item "Compresstor.app" of container window to {220, 250}
    set position of item "Applications" of container window to {540, 250}
    close
  end tell
end tell
EOF

log "detaching and compressing to UDZO"
hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$FINAL"
hdiutil convert "$TEMPLATE" -format UDZO -imagekey zlib-level=9 -o "$FINAL" >/dev/null
rm -f "$TEMPLATE"
rm -rf "$STAGING"

SIZE="$(du -h "$FINAL" | awk '{print $1}')"
log "done: $FINAL ($SIZE)"
