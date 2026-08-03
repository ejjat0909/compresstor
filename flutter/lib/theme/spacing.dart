// Layout scale — spacing, radii, and shadow tokens. Kept as bare constants
// so components can compose them without a BuildContext.

import 'package:flutter/material.dart';

import 'palette.dart';

class AppSpacing {
  const AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Standard component paddings picked to match the PySide6 rhythm.
  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  static const EdgeInsets buttonPaddingSm =
      EdgeInsets.symmetric(horizontal: 12, vertical: 5);
  static const EdgeInsets buttonPaddingLg =
      EdgeInsets.symmetric(horizontal: 22, vertical: 12);
  static const EdgeInsets inputPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  static const EdgeInsets cardPadding = EdgeInsets.all(20);
  static const EdgeInsets pagePadding = EdgeInsets.all(28);
}

class AppRadius {
  const AppRadius._();
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

List<BoxShadow> softShadow(AppPalette palette) => [
      BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 8)),
    ];
