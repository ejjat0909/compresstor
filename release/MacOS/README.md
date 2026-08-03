# Compresstor — macOS

**Requirements:** macOS 12.0 or newer (Intel or Apple Silicon).

## Install (drag & drop)

Prefer the disk image: `Compresstor-1.0.0.dmg`

1. Open the `.dmg` (double-click) — a Finder window shows the app
   over a dark background.
2. Drag `Compresstor.app` onto the `Applications` folder shortcut.
3. First launch: right-click the app → **Open**, then confirm in
   System Settings → Privacy & Security → "Open Anyway".
   (The app is unsigned — this is normal for locally built software.)

Alternative: copy `Compresstor.app` to your Applications folder
(or anywhere you like) and follow step 3.

## Usage

1. Drag PDF / image files onto the upload area (or Browse Files).
2. Pick a compression level and output mode.
3. Click **Compress Files**.
4. Compressed copies appear next to the originals (`name_compressed.ext`),
   in your chosen folder, or replace the originals when "overwrite" is set.

## Data

Settings and history are stored in:

    ~/Library/Application Support/Compresstor/

Delete that folder to reset everything.

## Building from source

See the project README (`scripts/build_macos.sh`). Build a universal2 binary:

    ./scripts/build_macos.sh

Package it into a distributable `.dmg` (drag-to-Applications installer):

    bash scripts/build_dmg.sh [version]   # → release/MacOS/Compresstor-<version>.dmg

## Troubleshooting

- "Compresstor cannot be opened": right-click → Open once (Gatekeeper).
- Files not compressing: make sure they are PDF, JPG, PNG, WebP, BMP, TIFF
  or GIF; password-protected PDFs must be unlocked first.
