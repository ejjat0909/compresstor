#!/bin/bash
# Install Compresstor.app to /Applications and strip quarantine.
# Double-click this file from the DMG to install.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/Compresstor.app"
DEST="/Applications/Compresstor.app"

if [ ! -d "$APP" ]; then
  echo "ERROR: Compresstor.app not found next to this script."
  exit 1
fi

echo "Installing Compresstor to /Applications..."

# Copy app to /Applications (needs sudo for /Applications)
if [ -d "$DEST" ]; then
  sudo rm -rf "$DEST"
fi
sudo cp -R "$APP" "$DEST"

# Strip quarantine so Gatekeeper doesn't block it
sudo xattr -cr "$DEST"

echo ""
echo "✓ Compresstor installed successfully!"
echo "  Opening Compresstor..."
open "$DEST"
