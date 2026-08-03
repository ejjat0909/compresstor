// Tabs — pill-style tabs. Mirrors QTabBar rules in styles.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spacing.dart';

class TabItem {
  const TabItem(this.id, this.label);
  final String id;
  final String label;
}

class AppTabs extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    required this.current,
    required this.onChanged,
  });

  final List<TabItem> tabs;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tab in tabs)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => onChanged(tab.id),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: tab.id == current ? palette.accentSoft : null,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Text(
                    tab.label,
                    style: theme.typography.body.copyWith(
                      color: tab.id == current
                          ? palette.text
                          : palette.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
