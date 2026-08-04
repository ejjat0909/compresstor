// Compresstor — Flutter frontend entry point.
//
// Wires the material theme, the AppTheme inherited widget, the app-wide
// [AppController] (queue + compression orchestration), and the shell.

import 'package:flutter/material.dart';

import 'shell/app_shell.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/typography.dart';

void main() {
  runApp(CompresstorApp(controller: AppController()));
}

class CompresstorApp extends StatelessWidget {
  const CompresstorApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const palette = darkPalette;
    final typography = AppTypography(palette);
    return AppScope(
      controller: controller,
      child: AppTheme(
        palette: palette,
        typography: typography,
        child: MaterialApp(
          title: 'Compresstor',
          debugShowCheckedModeBanner: false,
          theme: buildMaterialTheme(palette),
          home: const AppShell(),
        ),
      ),
    );
  }
}
