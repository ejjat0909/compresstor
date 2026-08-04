// Visual QA goldens (Phase 7) — render the REAL app shell (sidebar + header +
// page) with each page at a fixed desktop size and snapshot it, so layout
// nits (alignment, padding, ellipsis, overflow) can be eyeballed from
// test/goldens/*.png and regressions are caught by CI.
//
// Regenerate the baselines after intentional layout changes:
//   flutter test test/visual_qa_test.dart --update-goldens
// Then inspect test/goldens/*.png (e.g. open in an image viewer) and fix any
// nits on first pass, per the project's polish-sensitive convention.

import 'dart:io';

import 'package:compresstor/engine/models.dart';
import 'package:compresstor/shell/app_shell.dart';
import 'package:compresstor/state/app_controller.dart';
import 'package:compresstor/state/app_scope.dart';
import 'package:compresstor/theme/app_theme.dart';
import 'package:compresstor/theme/palette.dart';
import 'package:compresstor/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _viewport = Size(1280, 800);

Widget _harness(AppController controller) {
  const palette = darkPalette;
  return AppScope(
    controller: controller,
    child: AppTheme(
      palette: palette,
      typography: AppTypography(palette),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildMaterialTheme(palette),
        home: const AppShell(),
      ),
    ),
  );
}

/// A queue populated with varied names (long name exercises ellipsis) and a
/// couple of selections (exercises the selection toolbar).
AppController _dashboardController() {
  final tmp = Directory.systemTemp.createTempSync('visual_qa_dash');
  File('${tmp.path}/report-2026-Q3.pdf').writeAsBytesSync(List.filled(4 << 20, 7));
  File('${tmp.path}/a really long file name that should ellipsize in the queue.pdf')
      .writeAsBytesSync(List.filled(3 << 20, 7));
  File('${tmp.path}/photo.png').writeAsBytesSync(List.filled(2 << 20, 7));
  File('${tmp.path}/logo.png').writeAsBytesSync(List.filled(1 << 20, 7));

  final c = AppController(engine: FakeEngineClient(), autoLoadSettings: false);
  c.addPaths([
    '${tmp.path}/report-2026-Q3.pdf',
    '${tmp.path}/a really long file name that should ellipsize in the queue.pdf',
    '${tmp.path}/photo.png',
    '${tmp.path}/logo.png',
  ]);
  return c;
}

/// History with realistic rows incl. long paths + savings.
AppController _historyController() {
  final fake = FakeEngineClient();
  fake.setScript('history', const [
    {
      'type': 'history',
      'entries': [
        {
          'file_name': 'quarterly_financial_report_2026_with_appendices.pdf',
          'kind': 'pdf',
          'status': 'done',
          'original_size': 12500000,
          'compressed_size': 1800000,
          'savings_percent': 85.6,
          'timestamp': 1705276800.0, // fixed: renders as a date, deterministic
          'output_path': '/Users/alice/Documents/quarterly_financial_report_2026_with_appendices_compressed.pdf',
        },
        {
          'file_name': 'vacation_photo_kyoto.jpg',
          'kind': 'image',
          'status': 'done',
          'original_size': 4200000,
          'compressed_size': 920000,
          'savings_percent': 78.1,
          'timestamp': 1705190400.0,
          'output_path': '/Users/alice/Pictures/vacation_photo_kyoto_compressed.jpg',
        },
        {
          'file_name': 'scan_tiny.pdf',
          'kind': 'pdf',
          'status': 'skipped',
          'original_size': 880,
          'compressed_size': 880,
          'savings_percent': 0.0,
          'timestamp': 1705104000.0,
          'output_path': '',
        },
      ],
    },
  ]);
  final c = AppController(engine: fake, autoLoadSettings: false);
  return c;
}

/// Settings with a non-default accent + custom values so the controls show
/// their active states.
AppController _settingsController() {
  final c = AppController(engine: FakeEngineClient(), autoLoadSettings: false);
  c.settings = const AppSettings(
    accentColor: '#7c3aed',
    historyLimit: 100,
    defaultLevel: 'maximum',
    outputMode: 'overwrite',
    overwriteConfirmation: false,
  );
  return c;
}

void main() {
  testWidgets('golden: dashboard (queue + selection toolbar)', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = _dashboardController();
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    // Select two rows -> selection toolbar with "2 selected".
    await tester.tap(find.text('photo.png'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('logo.png'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/visual_dashboard.png'),
    );
  });

  testWidgets('golden: history (stats + table rows)', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = _historyController();
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle(); // history loads on a post-frame callback

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/visual_history.png'),
    );
  });

  testWidgets('golden: settings (appearance + defaults + about)', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = _settingsController();
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/visual_settings.png'),
    );
  });
}
