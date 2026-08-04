// Breadcrumbs — path navigation. Mirrors components/breadcrumbs.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';

class BreadcrumbItem {
  const BreadcrumbItem(this.label, {this.onTap});
  final String label;
  final VoidCallback? onTap;
}

class AppBreadcrumbs extends StatelessWidget {
  const AppBreadcrumbs({super.key, required this.items});

  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 6),
            AppIcon('chevron-right', size: 12, color: palette.textMuted),
            const SizedBox(width: 6),
          ],
          GestureDetector(
            onTap: items[i].onTap,
            child: MouseRegion(
              cursor: items[i].onTap == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: Text(
                items[i].label,
                style: theme.typography.caption.copyWith(
                  color: i == items.length - 1
                      ? palette.text
                      : palette.textSecondary,
                  fontWeight:
                      i == items.length - 1 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
