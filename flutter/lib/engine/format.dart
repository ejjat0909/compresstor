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

/// Human-readable relative timestamp, mirroring `format_timestamp` in the
/// Python utils. Shows "Just now", "5m ago", "3h ago", "Yesterday", or the
/// date for older entries.
String formatTimestamp(double epochSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(
    (epochSeconds * 1000).round(),
  );
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

/// Whether [epochSeconds] falls on today's date.
bool isToday(double epochSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(
    (epochSeconds * 1000).round(),
  );
  final now = DateTime.now();
  return dt.year == now.year && dt.month == now.month && dt.day == now.day;
}
