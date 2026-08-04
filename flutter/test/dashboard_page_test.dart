// Dashboard widget smoke tests: full page renders with a populated queue, and
// the Compress → progress → summary flow works against a fake engine (no
// Python spawned).

import 'dart:io';

import 'package:compresstor/components/button.dart';
import 'package:compresstor/components/toast.dart';
import 'package:compresstor/pages/dashboard_page.dart';
import 'package:compresstor/state/app_controller.dart';
import 'package:compresstor/theme/app_theme.dart';
import 'package:compresstor/theme/palette.dart';
import 'package:compresstor/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _harness(AppController controller) {
  const palette = darkPalette;
  return AppTheme(
    palette: palette,
    typography: AppTypography(palette),
    child: MaterialApp(
      theme: buildMaterialTheme(palette),
      home: ToastHost(
        child: Scaffold(body: DashboardPage(controller: controller)),
      ),
    ),
  );
}

void main() {
  late Directory tmp;
  late String pdfPath;
  late String pngPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dashboard_test');
    pdfPath = '${tmp.path}/report.pdf';
    pngPath = '${tmp.path}/photo.png';
    File(pdfPath).writeAsBytesSync(List.filled(2048, 7));
    File(pngPath).writeAsBytesSync(List.filled(1024, 9));
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const doneScript = [
    {'type': 'started', 'total': 2},
    {
      'type': 'file_done',
      'index': 0,
      'result': {
        'path': '/dev/null/a.pdf',
        'name': 'a.pdf',
        'kind': 'pdf',
        'status': 'done',
        'output_path': '/dev/null/a_compressed.pdf',
        'original_size': 2048,
        'compressed_size': 900,
        'error': '',
      },
    },
    {
      'type': 'file_done',
      'index': 1,
      'result': {
        'path': '/dev/null/b.png',
        'name': 'b.png',
        'kind': 'image',
        'status': 'done',
        'output_path': '/dev/null/b_compressed.png',
        'original_size': 1024,
        'compressed_size': 300,
        'error': '',
      },
    },
    {
      'type': 'finished',
      'results': [
        {
          'path': '/dev/null/a.pdf',
          'name': 'a.pdf',
          'kind': 'pdf',
          'status': 'done',
          'output_path': '/dev/null/a_compressed.pdf',
          'original_size': 2048,
          'compressed_size': 900,
          'error': '',
        },
        {
          'path': '/dev/null/b.png',
          'name': 'b.png',
          'kind': 'image',
          'status': 'done',
          'output_path': '/dev/null/b_compressed.png',
          'original_size': 1024,
          'compressed_size': 300,
          'error': '',
        },
      ],
    },
  ];

  Future<void> tapCompress(WidgetTester tester) async {
    final cta = find.widgetWithText(AppButton, 'Compress Files');
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pump();
  }

  // Drains the fake engine + toast timers, firing them incrementally so each
  // subsequent timer is scheduled inside the next time step.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 26; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('renders header, queue, settings and populated rows', (
    tester,
  ) async {
    final fake = FakeEngineClient();
    final c = AppController(engine: fake, autoLoadSettings: false);
    final result = c.addPaths([pdfPath, pngPath, '${tmp.path}/notes.txt']);
    expect(result.added.length, 2);
    expect(result.unsupported.length, 1);

    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    // "Compress Files" appears twice: the page title and the primary CTA.
    expect(find.text('Compress Files'), findsNWidgets(2));
    expect(find.text('Selected Files'), findsOneWidget);
    expect(find.text('Compression Settings'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(2));
  });

  testWidgets('Compress Files shows progress then summary', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('compress', doneScript);
    fake.emitDelay = const Duration(milliseconds: 150);
    final c = AppController(engine: fake, autoLoadSettings: false);
    c.addPaths([pdfPath, pngPath]);

    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    await tapCompress(tester);
    expect(find.text('Compressing files'), findsOneWidget);

    // Each fake event is delayed 150 ms — advance the clock step by step.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    // The toast and the summary modal both say "Compression complete".
    expect(find.text('Compression complete'), findsNWidgets(2));
    expect(find.textContaining('2 file(s) compressed'), findsNWidgets(2));
    expect(find.text('Done'), findsOneWidget);

    // Flush the fake engine's remaining timers so the test ends cleanly.
    await drain(tester);
  });

  testWidgets('Cancel mid-run flips the button to Cancelling…', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('compress', doneScript);
    fake.emitDelay = const Duration(milliseconds: 300);
    final c = AppController(engine: fake, autoLoadSettings: false);
    c.addPaths([pdfPath, pngPath]);

    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    await tapCompress(tester);
    expect(find.text('Compressing files'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(fake.cancelCalls, 1);
    expect(find.text('Cancelling…'), findsOneWidget);

    // Flush the fake engine's remaining timers so the test ends cleanly.
    await drain(tester);
  });

  testWidgets('nothing queued shows warning and disables the CTA', (
    tester,
  ) async {
    final c = AppController(
      engine: FakeEngineClient(),
      autoLoadSettings: false,
    );
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    final cta = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Compress Files'),
    );
    expect(cta.onPressed, isNull);

    await tester.ensureVisible(find.text('Clear queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear queue'));
    await tester.pump();
    // no crash, still rendered
    expect(find.text('Compress Files'), findsNWidgets(2));
  });
}
