# Compresstor — macOS

**Requirements:** macOS 12.0 or newer (Intel or Apple Silicon).

## Install

1. Copy `Compresstor.app` to your Applications folder (or anywhere you like).
2. First launch: right-click the app → **Open**, then confirm in
   System Settings → Privacy & Security → "Open Anyway".
   (The app is unsigned — this is normal for locally built software.)

## Usage

1. Drag PDF / image files onto the upload area (or Browse Files).
2. Pick a compression level and output mode.
3. Click **Compress Files**.
4. Compressed copies appear next to the originals (`name-compressed.ext`),
   in your chosen folder, or replace the originals when "overwrite" is set.

## Data

Settings and history are stored in:

    ~/Library/Application Support/Compresstor/

Delete that folder to reset everything.

## Building from source

See the project README (`scripts/build_macos.sh`). Build a universal2 binary:

    ./scripts/build_macos.sh

## Troubleshooting

- "Compresstor cannot be opened": right-click → Open once (Gatekeeper).
- Files not compressing: make sure they are PDF, JPG, PNG, WebP, BMP, TIFF
  or GIF; password-protected PDFs must be unlocked first.
