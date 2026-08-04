// Progress — themed linear progress bar. Mirrors QProgressBar styling.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';

enum ProgressTone { accent, success, danger }

class AppProgress extends StatelessWidget {
  const AppProgress({
    super.key,
    this.value,
    this.tone = ProgressTone.accent,
    this.height = 8,
  });

  /// `null` renders an indeterminate bar.
  final double? value;
  final ProgressTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppTheme.of(context).palette;
    final color = switch (tone) {
      ProgressTone.accent => palette.accent,
      ProgressTone.success => palette.success,
      ProgressTone.danger => palette.danger,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: palette.hover,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
