// Compresstor color tokens — ported from app/presentation/theme/palette.py.
//
// Compresstor is dark-only: there is no light palette. Every color the UI
// consumes goes through [AppPalette] so a single accent change re-themes the
// whole app.

import 'package:flutter/material.dart';

@immutable
class AppPalette {
  const AppPalette({
    // Surfaces
    required this.bg,
    required this.card,
    required this.cardHover,
    required this.input,
    required this.inputHover,
    // Borders
    required this.border,
    required this.borderSoft,
    required this.borderStrong,
    // Text
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    // Overlays
    required this.hover,
    required this.active,
    // Accent
    required this.accent,
    required this.accentHover,
    required this.accentActive,
    required this.accentSoft,
    required this.accentForeground,
    // Semantic
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.dangerHover,
    required this.info,
    required this.infoSoft,
    // Chrome
    required this.scrollbar,
    required this.scrollbarHover,
    required this.selection,
    required this.shadow,
    required this.skeleton,
    required this.header,
    required this.sidebar,
    required this.overlay,
    required this.backdrop,
  });

  // Surfaces
  final Color bg;
  final Color card;
  final Color cardHover;
  final Color input;
  final Color inputHover;
  // Borders
  final Color border;
  final Color borderSoft;
  final Color borderStrong;
  // Text
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  // Overlays
  final Color hover;
  final Color active;
  // Accent
  final Color accent;
  final Color accentHover;
  final Color accentActive;
  final Color accentSoft;
  final Color accentForeground;
  // Semantic
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color dangerHover;
  final Color info;
  final Color infoSoft;
  // Chrome
  final Color scrollbar;
  final Color scrollbarHover;
  final Color selection;
  final Color shadow;
  final Color skeleton;
  final Color header;
  final Color sidebar;
  final Color overlay;
  final Color backdrop;

  AppPalette copyWith({Color? accent}) {
    if (accent == null) return this;
    return AppPalette(
      bg: bg,
      card: card,
      cardHover: cardHover,
      input: input,
      inputHover: inputHover,
      border: border,
      borderSoft: borderSoft,
      borderStrong: borderStrong,
      text: text,
      textSecondary: textSecondary,
      textMuted: textMuted,
      textInverse: textInverse,
      hover: hover,
      active: active,
      accent: accent,
      accentHover: _darken(accent, 0.08),
      accentActive: _darken(accent, 0.16),
      accentSoft: accent.withValues(alpha: 0.16),
      accentForeground: accentForeground,
      success: success,
      successSoft: successSoft,
      warning: warning,
      warningSoft: warningSoft,
      danger: danger,
      dangerSoft: dangerSoft,
      dangerHover: dangerHover,
      info: info,
      infoSoft: infoSoft,
      scrollbar: scrollbar,
      scrollbarHover: scrollbarHover,
      selection: accent.withValues(alpha: 0.25),
      shadow: shadow,
      skeleton: skeleton,
      header: header,
      sidebar: sidebar,
      overlay: overlay,
      backdrop: backdrop,
    );
  }
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  final adjusted = hsl.withLightness(
    (hsl.lightness - amount).clamp(0.0, 1.0),
  );
  return adjusted.toColor();
}

const AppPalette darkPalette = AppPalette(
  bg: Color(0xFF020617),
  card: Color(0xFF0F172A),
  cardHover: Color(0xFF111C31),
  input: Color(0xFF0F172A),
  inputHover: Color(0xFF17223B),
  border: Color(0xFF1E293B),
  borderSoft: Color(0xFF16233A),
  borderStrong: Color(0xFF334155),
  text: Color(0xFFF1F5F9),
  textSecondary: Color(0xFF94A3B8),
  textMuted: Color(0xFF64748B),
  textInverse: Color(0xFFFFFFFF),
  hover: Color(0x0FF1F5F9),
  active: Color(0x1AF1F5F9),
  accent: Color(0xFF3B82F6),
  accentHover: Color(0xFF2563EB),
  accentActive: Color(0xFF1D4ED8),
  accentSoft: Color(0x293B82F6),
  accentForeground: Color(0xFFFFFFFF),
  success: Color(0xFF10B981),
  successSoft: Color(0x2410B981),
  warning: Color(0xFFF59E0B),
  warningSoft: Color(0x24F59E0B),
  danger: Color(0xFFEF4444),
  dangerSoft: Color(0x24EF4444),
  dangerHover: Color(0xFFDC2626),
  info: Color(0xFF38BDF8),
  infoSoft: Color(0x2438BDF8),
  scrollbar: Color(0x4D64748B),
  scrollbarHover: Color(0x8064748B),
  selection: Color(0x403B82F6),
  shadow: Color(0x66000000),
  skeleton: Color(0x3364748B),
  header: Color(0xFF0B1322),
  sidebar: Color(0xFF0B1322),
  overlay: Color(0x73000000),
  backdrop: Color(0x47000000),
);
