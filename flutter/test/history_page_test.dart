// History page tests: verify rendering, stats, and CRUD actions.

import 'package:compresstor/components/toast.dart';
import 'package:compresstor/pages/history_page.dart';
import 'package:compresstor/state/app_controller.dart';
import 'package:compresstor/state/app_scope.dart';
import 'package:compresstor/theme/app_theme.dart';
import 'package:compresstor/theme/palette.dart';
import 'package:compresstor/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _harness(AppController controller) {
  const palette = darkPalette;
  return AppScope(
    controller: controller,
    child: AppTheme(
      palette: palette,
      typography: AppTypography(palette),
      child: MaterialApp(
        theme: buildMaterialTheme(palette),
        home: const Scaffold(body: ToastHost(child: HistoryPage())),
      ),
    ),
  );
}

const _historyResponse = {
  'type': 'history',
  'entries': [
    {
      'file_name': 'report.pdf',
      'kind': 'pdf',
      'status': 'done',
      'original_size': 5000000,
      'compressed_size': 2000000,
      'savings_percent': 60.0,
      'timestamp': 1722700000.0,
      'output_path': '/tmp/report_compressed.pdf',
    },
    {
      'file_name': 'photo.jpg',
      'kind': 'image',
      'status': 'done',
      'original_size': 3000000,
      'compressed_size': 1500000,
      'savings_percent': 50.0,
      'timestamp': 1722690000.0,
      'output_path': '/tmp/photo_compressed.jpg',
    },
  ],
};

void main() {
  testWidgets('renders header, stats, and table rows', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('history', const [_historyResponse]);
    final c = AppController(engine: fake, autoLoadSettings: false);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Clear history'), findsOneWidget);

    // Stats strip
    expect(find.text('FILES'), findsOneWidget);
    expect(find.text('SAVED'), findsOneWidget);
    expect(find.text('AVG SAVINGS'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);

    // Table header
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);

    // Rows
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('60% smaller'), findsOneWidget);
    expect(find.text('50% smaller'), findsOneWidget);
  });

  testWidgets('empty state shows placeholder', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('history', const [
      {'type': 'history', 'entries': []},
    ]);
    final c = AppController(engine: fake, autoLoadSettings: false);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    expect(
      find.text('No history yet. Compress some files to see them here.'),
      findsOneWidget,
    );
  });

  testWidgets('clear history shows confirmation modal', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('history', const [_historyResponse]);
    final c = AppController(engine: fake, autoLoadSettings: false);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();

    expect(find.text('Clear history?'), findsOneWidget);
    expect(
      find.text(
        'All compression history will be removed. This cannot be undone.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('stats show correct values for 2 done entries', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('history', const [_historyResponse]);
    final c = AppController(engine: fake, autoLoadSettings: false);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    // 2 done files
    expect(find.text('2'), findsWidgets);
    // avg savings = (60+50)/2 = 55%
    expect(find.text('55%'), findsOneWidget);
  });

  testWidgets('row actions can remove an entry', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('history', const [_historyResponse]);
    final c = AppController(engine: fake, autoLoadSettings: false);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    // Open the actions menu on the first row, then Remove.
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from history'));
    await tester.pumpAndSettle();

    // Initial load (list) + remove (list) + reload (list) = 3 history calls.
    expect(fake.calls.where((s) => s == 'history').length, 3);
    expect(fake.calls, everyElement(contains('history')));
  });

  testWidgets('Refresh reloads history from the engine', (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('history', const [_historyResponse]);
    final c = AppController(engine: fake, autoLoadSettings: false);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    // initial load + refresh load = 2
    expect(fake.calls.where((s) => s == 'history').length, 2);
  });
}
