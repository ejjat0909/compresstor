// Widget tests for the Settings -> About update section: bundled version,
// check-for-updates flow, up-to-date state, failure toast, and the Update
// button driving the controller through download/progress/apply.
// RED phase — SettingsPage does not accept an updateController yet.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compresstor/components/toast.dart';
import 'package:compresstor/engine/update_applier.dart';
import 'package:compresstor/engine/update_client.dart';
import 'package:compresstor/pages/settings_page.dart';
import 'package:compresstor/state/app_controller.dart';
import 'package:compresstor/state/app_scope.dart';
import 'package:compresstor/state/update_controller.dart';
import 'package:compresstor/theme/app_theme.dart';
import 'package:compresstor/theme/palette.dart';
import 'package:compresstor/theme/typography.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

class FakeApplier implements UpdateApplier {
  int calls = 0;
  File? lastZip;

  @override
  Future<void> apply(File zip) async {
    calls++;
    lastZip = zip;
  }
}

const _latestUrl =
    'https://api.github.com/repos/ejjat0909/compresstor/releases/latest';

MockClient _releaseHandler({
  String tag = 'v1.0.1',
  String? shaLine,
  int fetchStatus = 200,
  Completer<void>? holdDownload,
}) {
  return MockClient((req) async {
    if (req.url.toString() == _latestUrl) {
      if (fetchStatus != 200) return http.Response('oops', fetchStatus);
      return http.Response(
        jsonEncode({
          'tag_name': tag,
          'body': 'Faster engine.\nSecond line.',
          'assets': [
            {
              'name': 'Compresstor-1.0.1-macos.zip',
              'browser_download_url':
                  'https://github.com/x/Compresstor-1.0.1-macos.zip',
            },
            {
              'name': 'Compresstor-1.0.1.sha256',
              'browser_download_url':
                  'https://github.com/x/Compresstor-1.0.1.sha256',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.url.path.endsWith('.sha256')) {
      final line = shaLine ?? _realShaLine();
      return http.Response('$line\n', 200);
    }
    if (holdDownload != null) await holdDownload.future;
    return http.Response.bytes(List<int>.filled(100, 7), 200);
  });
}

String _realShaLine() {
  final payload = List<int>.filled(100, 7);
  return '${sha256.convert(payload)}  Compresstor-1.0.1-macos.zip';
}

Widget _harness(AppController controller, UpdateController update) {
  const palette = darkPalette;
  return AppScope(
    controller: controller,
    child: AppTheme(
      palette: palette,
      typography: AppTypography(palette),
      child: MaterialApp(
        theme: buildMaterialTheme(palette),
        home: Scaffold(
          body: ToastHost(
            child: SettingsPage(updateController: update),
          ),
        ),
      ),
    ),
  );
}

Future<AppController> _appController() async {
  final fake = FakeEngineClient();
  fake.setScript('settings', const [
    {
      'type': 'settings',
      'settings': {
        'accent_color': '#3b82f6',
        'history_limit': 200,
        'default_level': 'balanced',
        'output_mode': 'suffix',
        'output_dir': '',
        'overwrite_confirmation': true,
        'add_to_history': true,
      },
    },
  ]);
  return AppController(engine: fake, autoLoadSettings: true);
}

void main() {
  testWidgets('About card shows the current version from the controller',
      (tester) async {
    final app = await _appController();
    final uc = UpdateController(
      client: UpdateClient(httpClient: _releaseHandler(), platform: 'macos'),
      applier: FakeApplier(),
      currentVersion: '9.9.9',
    );
    await tester.pumpWidget(_harness(app, uc));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version 9.9.9'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('Check for updates reveals the Update button when newer exists',
      (tester) async {
    final app = await _appController();
    final uc = UpdateController(
      client: UpdateClient(httpClient: _releaseHandler(), platform: 'macos'),
      applier: FakeApplier(),
      currentVersion: '1.0.0',
    );
    await tester.pumpWidget(_harness(app, uc));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.0.1 is available'), findsOneWidget);
    expect(find.textContaining('Faster engine'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
  });

  testWidgets('up to date shows a success toast and the latest caption',
      (tester) async {
    final app = await _appController();
    final uc = UpdateController(
      client: UpdateClient(httpClient: _releaseHandler(), platform: 'macos'),
      applier: FakeApplier(),
      currentVersion: '1.0.1', // latest == current
    );
    await tester.pumpWidget(_harness(app, uc));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('latest version'), findsWidgets);
    expect(find.text('You\u2019re up to date'), findsOneWidget);
    await drainToasts(tester);
  });

  testWidgets('check failure shows a danger toast', (tester) async {
    final app = await _appController();
    final uc = UpdateController(
      client:
          UpdateClient(httpClient: _releaseHandler(fetchStatus: 403), platform: 'macos'),
      applier: FakeApplier(),
      currentVersion: '1.0.0',
    );
    await tester.pumpWidget(_harness(app, uc));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn\u2019t check for updates'), findsOneWidget);
    await drainToasts(tester);
  });

  testWidgets(
      'Update downloads with progress, applies and resets the section',
      (tester) async {
    final app = await _appController();
    final applier = FakeApplier();
    final hold = Completer<void>();
    final uc = UpdateController(
      client: UpdateClient(
        httpClient: _releaseHandler(holdDownload: hold),
        platform: 'macos',
      ),
      applier: applier,
      currentVersion: '1.0.0',
    );
    await tester.pumpWidget(_harness(app, uc));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pump();

    // Mid-download: progress text visible.
    expect(find.textContaining('Downloading'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // The download writes + reads real temp files, which dart:io cannot
    // drive under FakeAsync. Alternate real-event-loop turns (runAsync) with
    // fake-zone flushes (pump) until the applier finally runs.
    hold.complete();
    for (var i = 0; i < 40 && applier.calls == 0; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(applier.calls, 1);
    expect(uc.status, UpdateStatus.relaunched);
    // Section resets to the check button.
    expect(find.text('Check for updates'), findsOneWidget);
  });
}
