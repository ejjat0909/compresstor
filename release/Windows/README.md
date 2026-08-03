# Compresstor — Windows

**Requirements:** Windows 10 (21H2 or newer) or Windows 11, 64-bit.

## Install

1. Copy the `Compresstor` folder anywhere (e.g. `C:\Program Files\` or your
   Desktop).
2. Run `Compresstor.exe`.

No installation wizard needed — the app is portable.

## Usage

1. Drag PDF / image files onto the upload area (or Browse Files).
2. Pick a compression level and output mode.
3. Click **Compress Files**.
4. Compressed copies appear next to the originals (`name-compressed.ext`),
   in your chosen folder, or replace the originals when "overwrite" is set.

## Data

Settings and history are stored in:

    %APPDATA%\Compresstor\

Delete that folder to reset everything.

## Building from source

On a Windows machine, run from the repo root:

    scripts\build_windows.bat

## Troubleshooting

- SmartScreen warning on first run: More info → Run anyway (unsigned app).
- Files not compressing: make sure they are PDF, JPG, PNG, WebP, BMP, TIFF
  or GIF; password-protected PDFs must be unlocked first.
