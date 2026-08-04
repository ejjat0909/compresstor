// Unit tests for the engine wire models: enum mapping, JSON mapping of the
// compress request (must match docs/engine-protocol.md), JobResult parsing,
// level presets, and formatSize parity with the Python implementation.

import 'package:compresstor/engine/format.dart';
import 'package:compresstor/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectKind', () {
    test('classifies PDFs', () {
      expect(detectKind('/a/b/report.pdf'), FileKind.pdf);
      expect(detectKind('/a/b/REPORT.PDF'), FileKind.pdf);
    });

    test('classifies images', () {
      for (final ext in [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'bmp',
        'tif',
        'tiff',
        'gif',
      ]) {
        expect(detectKind('/a/b/photo.$ext'), FileKind.image, reason: ext);
      }
    });

    test('rejects anything else', () {
      expect(detectKind('/a/b/notes.txt'), FileKind.unsupported);
      expect(detectKind('/a/b/noext'), FileKind.unsupported);
    });
  });

  group('CompressionOptions.toJson', () {
    test('maps to the documented protocol field names', () {
      const options = CompressionOptions(
        level: CompressionLevel.balanced,
        outputMode: OutputMode.directory,
        outputDir: '/out',
        suffix: '_c',
        maxSizeMb: 5,
        pdf: PdfOptions(imageQuality: 70, maxImageDpi: 144),
        image: ImageOptions(quality: 72, resizeMax: 0),
      );
      final json = options.toJson();
      expect(json['level'], 'balanced');
      expect(json['output_mode'], 'directory');
      expect(json['output_dir'], '/out');
      expect(json['suffix'], '_c');
      expect(json['max_size_mb'], 5);
      expect(json['pdf'], {
        'image_quality': 70,
        'max_image_dpi': 144,
        'remove_metadata': true,
        'deflate': true,
        'garbage': 4,
      });
      expect(json['image'], {
        'quality': 72,
        'resize_max': 0,
        'preserve_format': true,
        'strip_metadata': true,
      });
    });

    test('targetBytes follows the Python math', () {
      expect(
        const CompressionOptions(maxSizeMb: 5).targetBytes,
        5 * 1024 * 1024,
      );
      expect(const CompressionOptions().targetBytes, isNull);
    });
  });

  group('JobResult.fromJson', () {
    test('parses a done result', () {
      final r = JobResult.fromJson(const {
        'path': '/a.pdf',
        'name': 'a.pdf',
        'kind': 'pdf',
        'status': 'done',
        'output_path': '/a_compressed.pdf',
        'original_size': 10485760,
        'compressed_size': 4194304,
        'error': '',
      });
      expect(r.kind, FileKind.pdf);
      expect(r.status, JobStatus.done);
      expect(r.outputPath, '/a_compressed.pdf');
      expect(r.savingsPercent, 60.0);
      expect(r.savings, 10485760 - 4194304);
    });

    test('clamps savings to zero', () {
      final r = JobResult.fromJson(const {
        'path': '/b.png',
        'name': 'b.png',
        'kind': 'image',
        'status': 'done',
        'output_path': '/b.png',
        'original_size': 100,
        'compressed_size': 200,
        'error': '',
      });
      expect(r.savings, 0);
      expect(r.savingsPercent, 0);
    });
  });

  group('levelPresets', () {
    test('match the Python _LEVEL_PRESETS numbers', () {
      expect(levelPresets[CompressionLevel.high]!.pdf.imageQuality, 85);
      expect(levelPresets[CompressionLevel.high]!.pdf.maxImageDpi, 180);
      expect(levelPresets[CompressionLevel.high]!.image.quality, 82);
      expect(levelPresets[CompressionLevel.balanced]!.pdf.imageQuality, 70);
      expect(levelPresets[CompressionLevel.maximum]!.pdf.imageQuality, 50);
      expect(levelPresets[CompressionLevel.maximum]!.pdf.maxImageDpi, 100);
    });
  });

  group('formatSize', () {
    test('parity with the Python format_size', () {
      expect(formatSize(0), '0 B');
      expect(formatSize(512), '512 B');
      expect(formatSize(2048), '2.0 KB');
      expect(formatSize(1048576), '1.0 MB');
      expect(formatSize(10 * 1024 * 1024), '10.0 MB');
    });
  });

  group('AppSettings.fromJson', () {
    test('parses engine settings payload', () {
      final s = AppSettings.fromJson(const {
        'theme': 'dark',
        'accent_color': '#3b82f6',
        'history_limit': 100,
        'default_level': 'maximum',
        'output_mode': 'overwrite',
        'output_dir': '/x',
        'overwrite_confirmation': false,
        'add_to_history': false,
      });
      expect(s.defaultCompressionLevel, CompressionLevel.maximum);
      expect(s.defaultOutputMode, OutputMode.overwrite);
      expect(s.overwriteConfirmation, isFalse);
      expect(s.addToHistory, isFalse);
    });

    test('falls back to defaults on missing fields', () {
      final s = AppSettings.fromJson(const {});
      expect(s.defaultCompressionLevel, CompressionLevel.balanced);
      expect(s.defaultOutputMode, OutputMode.suffix);
      expect(s.overwriteConfirmation, isTrue);
    });
  });
}
