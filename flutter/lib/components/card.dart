// Card — bordered surface. Mirrors QFrame[ui="card"] rules in styles.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.subtle = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.of(context).palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: subtle ? palette.cardHover : palette.card,
        borderRadius: AppRadius.xlAll,
        border: Border.all(
          color: subtle ? palette.borderSoft : palette.border,
        ),
      ),
      child: child,
    );
  }
}
