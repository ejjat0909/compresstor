// Compresstor — Flutter frontend entry point.
//
// Wires the material theme, the AppTheme inherited widget, the app-wide
// [AppController] (queue + compression orchestration), and the shell.
// Listens to settings changes so the accent color updates live.

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

class CompresstorApp extends StatefulWidget {
  const CompresstorApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<CompresstorApp> createState() => _CompresstorAppState();
}

class _CompresstorAppState extends State<CompresstorApp> {
  late String _lastAccent;

  @override
  void initState() {
    super.initState();
    _lastAccent = widget.controller.settings.accentColor;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final accent = widget.controller.settings.accentColor;
    if (accent != _lastAccent) {
      _lastAccent = accent;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentHex = widget.controller.settings.accentColor;
    final palette = _applyAccent(darkPalette, accentHex);
    final typography = AppTypography(palette);
    return AppScope(
      controller: widget.controller,
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

AppPalette _applyAccent(AppPalette base, String hex) {
  if (hex.isEmpty || hex == '#3b82f6') return base;
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return base;
  final parsed = int.tryParse('FF$clean', radix: 16);
  if (parsed == null) return base;
  return base.copyWith(accent: Color(parsed));
}
