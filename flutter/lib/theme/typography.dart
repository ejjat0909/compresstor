// Text styles mirroring app/presentation/theme/styles.py QLabel[ui="..."] rules.
//
// Sizes are in logical pixels (Flutter) rather than pt; the Qt sizes were
// point-based, so we convert with the standard 1 pt ≈ 1.333 px factor. The
// resulting rhythm matches the PySide6 app closely enough for visual parity.

import 'package:flutter/material.dart';

import 'palette.dart';

class AppTypography {
  const AppTypography(this.palette);
  final AppPalette palette;

  static const String fontFamily = 'Inter';

  TextStyle get pageTitle => TextStyle(
        fontFamily: fontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: palette.text,
        height: 1.2,
      );

  TextStyle get sectionTitle => TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: palette.text,
        height: 1.25,
      );

  TextStyle get cardTitle => TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: palette.text,
        height: 1.3,
      );

  TextStyle get body => TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: palette.text,
        height: 1.45,
      );

  TextStyle get bodyStrong => body.copyWith(fontWeight: FontWeight.w600);

  TextStyle get secondary => body.copyWith(color: palette.textSecondary);

  TextStyle get caption => TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: palette.textMuted,
        height: 1.4,
      );

  TextStyle get muted => body.copyWith(color: palette.textMuted);

  TextStyle get button => TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: palette.text,
      );
}
