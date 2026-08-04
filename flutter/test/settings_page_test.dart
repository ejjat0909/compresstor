// Settings page tests: verify rendering, save, and reset.

import 'package:compresstor/components/toast.dart';
import 'package:compresstor/pages/settings_page.dart';
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
        home: const Scaffold(body: ToastHost(child: SettingsPage())),
      ),
    ),
  );
}

void main() {
  testWidgets('renders all settings sections', (tester) async {
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
    final c = AppController(engine: fake, autoLoadSettings: true);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Compression Defaults'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
  });

  testWidgets('save button renders and is present', (tester) async {
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
    final c = AppController(engine: fake, autoLoadSettings: true);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    // Save button exists (even if scrolled off-screen)
    expect(find.text('Save settings'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
  });

  testWidgets('accent swatches render', (tester) async {
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
    final c = AppController(engine: fake, autoLoadSettings: true);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    expect(find.text('ACCENT COLOR'), findsOneWidget);
    expect(find.text('Custom…'), findsOneWidget);
  });

  testWidgets('changing default level then Save sends a settings set request',
      (tester) async {
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
    final c = AppController(engine: fake, autoLoadSettings: true);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    // Open the default-level dropdown and pick Maximum.
    await tester.tap(find.text('Balanced — recommended'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maximum — smallest size'));
    await tester.pumpAndSettle();

    // Save (the actions row sits below the fold — scroll it into view).
    await tester.ensureVisible(find.text('Save settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();

    expect(fake.lastRequestMap?['action'], 'set');
    final sent = fake.lastRequestMap?['settings'] as Map<String, dynamic>;
    expect(sent['default_level'], 'maximum');
    expect(sent['accent_color'], '#3b82f6');
    expect(sent['history_limit'], 200);

    await drainToasts(tester);
  });

  testWidgets('Reset to defaults sends a settings set with defaults',
      (tester) async {
    final fake = FakeEngineClient();
    fake.setScript('settings', const [
      {
        'type': 'settings',
        'settings': {
          'accent_color': '#e11d48',
          'history_limit': 50,
          'default_level': 'maximum',
          'output_mode': 'overwrite',
          'output_dir': '/custom',
          'overwrite_confirmation': false,
          'add_to_history': false,
        },
      },
    ]);
    final c = AppController(engine: fake, autoLoadSettings: true);
    await tester.pumpWidget(_harness(c));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(fake.lastRequestMap?['action'], 'set');
    final sent = fake.lastRequestMap?['settings'] as Map<String, dynamic>;
    expect(sent['default_level'], 'balanced');
    expect(sent['accent_color'], '#3b82f6');
    expect(sent['history_limit'], 200);
    expect(sent['overwrite_confirmation'], isTrue);
    expect(sent['add_to_history'], isTrue);

    await drainToasts(tester);
  });
}
