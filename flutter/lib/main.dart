// Compresstor — Flutter frontend entry point (Phase 2 shell).
//
// The Phase 0 hello-world spike (single-screen engine invoker) has moved into
// [DashboardPage] et al. This file wires the material theme, the AppTheme
// inherited widget, and the shell.

import 'package:flutter/material.dart';

import 'shell/app_shell.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/typography.dart';

void main() {
  runApp(const CompresstorApp());
}

class CompresstorApp extends StatelessWidget {
  const CompresstorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const palette = darkPalette;
    final typography = AppTypography(palette);
    return AppTheme(
      palette: palette,
      typography: typography,
      child: MaterialApp(
        title: 'Compresstor',
        debugShowCheckedModeBanner: false,
        theme: buildMaterialTheme(palette),
        home: const AppShell(),
      ),
    );
  }
}
