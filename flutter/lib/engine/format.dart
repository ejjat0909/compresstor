// Formatting utilities, mirroring app/presentation/components/utils.py.

/// Human-readable file size (B, KB, MB, GB, TB) — identical output to the
/// Python `format_size` so the UI shows the same strings as the Qt app.
String formatSize(int numBytes) {
  double size = numBytes.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  for (final unit in units) {
    if (size < 1024 || unit == 'TB') {
      if (unit == 'B') return '${size.round()} B';
      return '${size.toStringAsFixed(1)} $unit';
    }
    size /= 1024;
  }
  return '${size.toStringAsFixed(1)} TB';
}
