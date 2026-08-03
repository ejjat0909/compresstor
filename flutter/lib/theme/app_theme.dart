// Central theme wiring: exposes the palette / typography / accent via
// [AppTheme], and produces the Material [ThemeData] for MaterialApp.

import 'package:flutter/material.dart';

import 'palette.dart';
import 'spacing.dart';
import 'typography.dart';

class AppTheme extends InheritedWidget {
  const AppTheme({
    super.key,
    required this.palette,
    required this.typography,
    required super.child,
  });

  final AppPalette palette;
  final AppTypography typography;

  static AppTheme of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(result != null, 'AppTheme.of() called outside an AppTheme scope');
    return result!;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) =>
      palette != oldWidget.palette || typography != oldWidget.typography;
}

/// Builds a Material [ThemeData] whose colors line up with [palette] so that
/// unstyled Material widgets (dialogs, menus, cursors) don't look foreign.
ThemeData buildMaterialTheme(AppPalette palette) {
  final scheme = ColorScheme.dark(
    primary: palette.accent,
    onPrimary: palette.accentForeground,
    secondary: palette.accent,
    onSecondary: palette.accentForeground,
    surface: palette.card,
    onSurface: palette.text,
    error: palette.danger,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.bg,
    canvasColor: palette.bg,
    fontFamily: AppTypography.fontFamily,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.selection,
      selectionHandleColor: palette.accent,
    ),
    dividerColor: palette.border,
    splashFactory: InkSparkle.splashFactory,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.text,
        borderRadius: AppRadius.smAll,
      ),
      textStyle: TextStyle(
        color: palette.bg,
        fontSize: 12,
        fontFamily: AppTypography.fontFamily,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    iconTheme: IconThemeData(color: palette.textSecondary, size: 18),
  );
}
