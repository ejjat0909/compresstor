#!/usr/bin/env bash
# build_pkg.sh — package Compresstor.app into a .pkg installer.
#
# The .pkg installs to /Applications and runs a postinstall script that
# strips quarantine (xattr -cr) so the app opens without Gatekeeper issues.
#
# Usage:  bash scripts/build_pkg.sh [version]
# Input:  release/MacOS/Compresstor.app (built by build_macos.sh)
# Output: release/Compresstor-<version>.pkg

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.0}"
APP="$ROOT/release/MacOS/Compresstor.app"
PKG="$ROOT/release/Compresstor-$VERSION.pkg"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found — run build_macos.sh first" >&2
  exit 1
fi

echo "==> Building .pkg installer (v$VERSION)..."

# Create a temporary payload root with the app in Applications/
PAYLOAD="$(mktemp -d)"
mkdir -p "$PAYLOAD/Applications"
cp -R "$APP" "$PAYLOAD/Applications/Compresstor.app"

# Build the component pkg
pkgbuild \
  --root "$PAYLOAD" \
  --scripts "$ROOT/packaging/macos/scripts" \
  --identifier "com.compresstor.app" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG"

rm -rf "$PAYLOAD"

echo "==> Done: $PKG ($(du -h "$PKG" | awk '{print $1}'))"
