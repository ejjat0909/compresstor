// Badge — small pill for status/tags. Mirrors components/badge.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';

enum BadgeTone { neutral, accent, success, warning, danger, info }

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
  });

  final String label;
  final BadgeTone tone;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    final (bg, fg) = _colors(palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.smAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(AppPalette p) {
    switch (tone) {
      case BadgeTone.neutral:
        return (p.hover, p.textSecondary);
      case BadgeTone.accent:
        return (p.accentSoft, p.accent);
      case BadgeTone.success:
        return (p.successSoft, p.success);
      case BadgeTone.warning:
        return (p.warningSoft, p.warning);
      case BadgeTone.danger:
        return (p.dangerSoft, p.danger);
      case BadgeTone.info:
        return (p.infoSoft, p.info);
    }
  }
}
