#!/usr/bin/env bash
# One-command GitHub release for Compresstor (update source — Option A,
# docs/update-plan.md). Run AFTER building on macOS and/or Windows:
#
#   ./scripts/publish_release.sh
#
# Reads version.json, uploads the platform zips + sha256 file as assets of
# release v<ver>, marking it latest. Release notes: RELEASE_NOTES.md if
# present (first line is shown in the app's About card), otherwise a short
# fallback. Requires the gh CLI (https://cli.github.com) and gh auth login.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v gh >/dev/null || { echo "gh CLI not found — install from https://cli.github.com"; exit 1; }

VER=$("${PYTHON:-python3}" -c "import json;print(json.load(open('version.json'))['version'])")
TAG="v$VER"
SHA="release/Compresstor-$VER.sha256"

[ -f "$SHA" ] || { echo "Missing $SHA — run the build script first."; exit 1; }

ASSETS=()
[ -f "release/Compresstor-$VER-macos.zip" ]   && ASSETS+=("release/Compresstor-$VER-macos.zip")
[ -f "release/Compresstor-$VER-windows.zip" ] && ASSETS+=("release/Compresstor-$VER-windows.zip")
[ "${#ASSETS[@]}" -gt 0 ] || { echo "No platform zips found in release/ — run the build script first."; exit 1; }
ASSETS+=("$SHA")

echo "==> Releasing $TAG with: ${ASSETS[*]}"
if [ -f RELEASE_NOTES.md ]; then
  gh release create "$TAG" "${ASSETS[@]}" \
    --title "Compresstor $VER" --latest -F RELEASE_NOTES.md
else
  gh release create "$TAG" "${ASSETS[@]}" \
    --title "Compresstor $VER" --latest --notes "Compresstor $VER"
fi

echo "==> Released:"
gh release view "$TAG"
echo "The About card will now offer v$VER to users on Check for updates."
