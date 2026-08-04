// Phase 2 smoke test: pumps the shell with each page and asserts landmarks
// render. Engine calls are network-free (they spawn a process) but the
// widgets do not await them synchronously, so a single frame is enough.

import 'package:compresstor/components/badge.dart';
import 'package:compresstor/components/button.dart';
import 'package:compresstor/components/card.dart';
import 'package:compresstor/theme/app_theme.dart';
import 'package:compresstor/theme/palette.dart';
import 'package:compresstor/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _themed(Widget child) {
  const palette = darkPalette;
  return AppTheme(
    palette: palette,
    typography: AppTypography(palette),
    child: MaterialApp(
      theme: buildMaterialTheme(palette),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('AppButton renders label and fires callback', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_themed(
      AppButton(label: 'Go', onPressed: () => pressed++),
    ));
    expect(find.text('Go'), findsOneWidget);
    await tester.tap(find.text('Go'));
    expect(pressed, 1);
  });

  testWidgets('AppBadge renders label', (tester) async {
    await tester.pumpWidget(_themed(
      const AppBadge(label: 'Beta', tone: BadgeTone.accent),
    ));
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('AppCard wraps its child', (tester) async {
    await tester.pumpWidget(_themed(
      const AppCard(child: Text('inside')),
    ));
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('AppButton disabled state has null onPressed callback', (tester) async {
    await tester.pumpWidget(_themed(
      const AppButton(label: 'Nope', onPressed: null),
    ));
    // Tap should not throw and no callback wired.
    await tester.tap(find.text('Nope'));
  });
}
