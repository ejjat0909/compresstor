// Tests for format.dart utilities.

import 'package:compresstor/engine/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSize', () {
    test('bytes', () => expect(formatSize(500), '500 B'));
    test('kilobytes', () => expect(formatSize(2048), '2.0 KB'));
    test('megabytes', () => expect(formatSize(5242880), '5.0 MB'));
  });

  group('formatTimestamp', () {
    test('very recent shows Just now', () {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      expect(formatTimestamp(now), 'Just now');
    });

    test('minutes ago', () {
      final ts = DateTime.now()
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch /
          1000;
      expect(formatTimestamp(ts), '5m ago');
    });

    test('hours ago', () {
      final ts = DateTime.now()
              .subtract(const Duration(hours: 3))
              .millisecondsSinceEpoch /
          1000;
      expect(formatTimestamp(ts), '3h ago');
    });

    test('yesterday', () {
      final ts = DateTime.now()
              .subtract(const Duration(hours: 30))
              .millisecondsSinceEpoch /
          1000;
      expect(formatTimestamp(ts), 'Yesterday');
    });

    test('older dates show YYYY-MM-DD', () {
      // 2024-01-15 00:00:00 UTC
      const ts = 1705276800.0;
      final result = formatTimestamp(ts);
      expect(result, contains('2024'));
    });
  });

  group('isToday', () {
    test('now is today', () {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      expect(isToday(now.toDouble()), isTrue);
    });

    test('yesterday is not today', () {
      final ts = DateTime.now()
              .subtract(const Duration(hours: 48))
              .millisecondsSinceEpoch /
          1000;
      expect(isToday(ts.toDouble()), isFalse);
    });
  });
}
