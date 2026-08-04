// Phase 5 integration test — drives the REAL app UI against the REAL Python
// engine binary (PyMuPDF + Pillow) and asserts the full Phase 5 contract:
//   - a batch compresses end to end through the dashboard UI
//   - every output file exists on disk
//   - every output is smaller than its input (size shrank)
//   - the engine persisted the run to history (history row added)
//
// Run (macOS desktop; the engine's JSON stores are isolated to a temp dir so
// real user history/settings are never touched):
//
//   flutter test integration_test/compression_flow_test.dart -d macos
//
// Requires the repo .venv (PyMuPDF/Pillow) — the client auto-discovers it.

import 'dart:convert';
import 'dart:io';

import 'package:compresstor/components/button.dart';
import 'package:compresstor/engine/engine_client.dart';
import 'package:compresstor/engine/models.dart';
import 'package:compresstor/main.dart';
import 'package:compresstor/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

String get _venvPython {
  final here = Directory.current.path;
  final root = here.endsWith('flutter') ? Directory(here).parent.path : here;
  final candidate = '$root/.venv/bin/python';
  return File(candidate).existsSync() ? candidate : 'python3';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final tmp = Directory.systemTemp.createTempSync('compresstor_it');
  final dataDir = Directory('${tmp.path}/data')..createSync();
  final filesDir = Directory('${tmp.path}/files')..createSync();

  late String pdfPath;
  late String jpgPath;

  setUpAll(() async {
    // Image-rich fixtures so the engine has real work to shrink: a big noisy
    // JPEG plus a 3-page PDF that embeds it.
    final py = _venvPython;
    final gen = '''
import os
from PIL import Image, ImageDraw
import fitz

FILES = r"${filesDir.path}"
img = Image.new("RGB", (1600, 1200), (120, 130, 140))
d = ImageDraw.Draw(img)
for i in range(2000):
    x, y = i * 7 % 1600, i * 11 % 1200
    d.ellipse([x, y, x + 40, y + 40], fill=(i % 255, (i * 2) % 255, (i * 3) % 255))
jpg = os.path.join(FILES, "photo.jpg")
img.save(jpg, "JPEG", quality=100, subsampling=0)

doc = fitz.open()
for _ in range(3):
    page = doc.new_page(width=595, height=842)
    page.insert_text((72, 100), "Compresstor integration fixture", fontsize=24)
    page.insert_image(fitz.Rect(72, 150, 400, 350), filename=jpg)
pdf = os.path.join(FILES, "doc.pdf")
doc.save(pdf, garbage=0, deflate=False)
doc.close()
''';
    final r = await Process.run(py, ['-c', gen]);
    expect(r.exitCode, 0, reason: 'fixture generation failed: ${r.stderr}');
    pdfPath = '${filesDir.path}/doc.pdf';
    jpgPath = '${filesDir.path}/photo.jpg';
    expect(File(pdfPath).existsSync(), isTrue);
    expect(File(jpgPath).existsSync(), isTrue);
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Pumps frames until any of [finders] matches or [timeout] elapses.
  Future<void> pumpUntilAny(
    WidgetTester tester,
    List<Finder> finders, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      for (final f in finders) {
        if (f.evaluate().isNotEmpty) return;
      }
    }
    throw TestFailure('Timed out waiting for any of $finders');
  }

  /// Pumps frames until [finder] matches or [timeout] elapses.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 45),
  }) => pumpUntilAny(tester, [finder], timeout: timeout);

  testWidgets('full batch compress via the real engine: file exists, size '
      'shrank, history row added', (tester) async {
    // Desktop test windows default small — size the viewport so the whole
    // dashboard (queue table + options panel + CTA) fits on one screen.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Isolated engine: JSON stores go to a temp dir, never real user data.
    final engine = EngineClient(
      environment: {'COMPRESSTOR_DATA_DIR': dataDir.path},
    );
    final controller = AppController(engine: engine, autoLoadSettings: true);

    await tester.pumpWidget(CompresstorApp(controller: controller));
    await tester.pumpAndSettle();

    final added = controller.addPaths([pdfPath, jpgPath]);
    expect(added.added, hasLength(2));
    await tester.pumpAndSettle();
    expect(find.text('doc.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);

    // Start the batch through the UI.
    final cta = find.widgetWithText(AppButton, 'Compress Files');
    expect(cta, findsOneWidget);
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pump();

    // The engine may finish before the first frame — accept the running modal
    // OR the summary modal, then wait for the summary.
    await pumpUntilAny(tester, [
      find.text('Compressing files'),
      find.text('Compression complete'),
    ]);
    await pumpUntilFound(tester, find.text('Compression complete'));

    // The engine finished: results carry the real file sizes.
    expect(controller.lastError, isNull);
    final results = controller.lastResults;
    expect(results, isNotNull);
    expect(results, hasLength(2));

    final byName = {for (final r in results!) r.name: r};
    for (final name in ['doc.pdf', 'photo.jpg']) {
      final r = byName[name]!;
      expect(r.status, JobStatus.done, reason: '$name should compress');
      expect(r.originalSize, greaterThan(0));
      expect(
        r.compressedSize,
        lessThan(r.originalSize),
        reason: '$name did not shrink',
      );
      expect(
        File(r.outputPath).existsSync(),
        isTrue,
        reason: 'engine claimed output ${r.outputPath} but it does not exist',
      );
    }

    // History row added: the engine persisted the run into the isolated
    // data dir (add_to_history defaults to true).
    final historyFile = File('${dataDir.path}/history.json');
    expect(historyFile.existsSync(), isTrue, reason: 'history.json written');
    final history = jsonDecode(historyFile.readAsStringSync()) as List;
    final outputPaths = history
        .map((e) => (e as Map<String, dynamic>)['output_path'] as String)
        .toSet();
    expect(outputPaths, containsAll([byName['doc.pdf']!.outputPath, byName['photo.jpg']!.outputPath]));

    // Close the summary modal so the test ends with a settled tree (tolerant:
    // the modal may sit outside the small default window's hit area).
    final doneBtn = find.widgetWithText(AppButton, 'Done');
    if (doneBtn.evaluate().isNotEmpty) {
      await tester.tap(doneBtn, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
  });
}
