// Real end-to-end test of the EngineClient + Python engine CLI (Phase 3 exit
// criterion: "a full batch compresses through the engine with live progress
// and correct output paths").
//
// Requires the repo's .venv (PyMuPDF/Pillow) — the client auto-discovers it.
// Run with: flutter test test/engine_integration_test.dart

import 'dart:io';

import 'package:compresstor/engine/engine_client.dart';
import 'package:compresstor/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

String _venvPython() {
  final here = Directory.current.path;
  final root = here.endsWith('flutter') ? Directory(here).parent.path : here;
  final candidate = '$root/.venv/bin/python';
  return File(candidate).existsSync() ? candidate : 'python3';
}

void main() {
  final dir = Directory.systemTemp.createTempSync('compresstor_e2e');
  late String fixturePdf;

  setUpAll(() async {
    // Build a real PDF through the engine's venv (PyMuPDF), like the Python
    // test fixtures do. If the venv is missing this suite fails loudly.
    final py = _venvPython();
    final gen =
        '''
import fitz
doc = fitz.open()
page = doc.new_page(width=612, height=792)
for i in range(3):
    page.insert_text((72, 100 + i * 50), f"Compresstor e2e fixture page {i}", fontsize=24)
doc.save(r"${dir.path}/fixture.pdf")
''';
    final r = await Process.run(py, ['-c', gen]);
    expect(r.exitCode, 0, reason: 'fixture generation failed: ${r.stderr}');
    fixturePdf = '${dir.path}/fixture.pdf';
  });

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'compress via real engine produces an output file',
    () async {
      final client = EngineClient();
      final events = <Map<String, dynamic>>[];
      final sawStarted = <String>[];
      final sawProgress = <String>[];

      await for (final event in client.run(
        'compress',
        request: {
          'items': [
            {'path': fixturePdf},
          ],
          'options': const CompressionOptions(
            level: CompressionLevel.balanced,
            outputMode: OutputMode.suffix,
            suffix: '_compressed',
          ).toJson(),
          'add_to_history': false,
        },
      )) {
        events.add(event);
        if (event['type'] == 'started') sawStarted.add('started');
        if (event['type'] == 'progress') sawProgress.add('progress');
        if (event['type'] == 'file_done') {
          final result = event['result'] as Map<String, dynamic>;
          final out = result['output_path'] as String;
          expect(
            File(out).existsSync(),
            isTrue,
            reason: 'engine claimed output $out but it does not exist',
          );
          expect(result['original_size'], greaterThan(0));
        }
      }

      expect(sawStarted, isNotEmpty);
      expect(sawProgress, isNotEmpty, reason: 'expected progress events');
      final finished = events.where((e) => e['type'] == 'finished').toList();
      expect(finished, hasLength(1));
      final results = finished.single['results'] as List;
      expect(results, hasLength(1));
      final first = results.single as Map<String, dynamic>;
      expect(first['status'], anyOf('done', 'skipped'));
      expect(first['output_path'], endsWith('fixture_compressed.pdf'));
      expect(File(first['output_path'] as String).existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'settings get round-trips through the real engine',
    () async {
      final client = EngineClient();
      Map<String, dynamic>? settings;
      await for (final event in client.run(
        'settings',
        request: {'action': 'get'},
      )) {
        if (event['type'] == 'settings') {
          settings = event['settings'] as Map<String, dynamic>;
        }
      }
      expect(settings, isNotNull);
      final captured = settings!;
      expect(captured['default_level'], isA<String>());
      expect(captured['history_limit'], isA<int>());
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
