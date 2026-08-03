// Context menu — thin wrapper over PopupMenuButton with themed styling.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spacing.dart';

class AppMenuItem<T> {
  const AppMenuItem({required this.value, required this.label, this.destructive = false});
  final T value;
  final String label;
  final bool destructive;
}

class AppContextMenu<T> extends StatelessWidget {
  const AppContextMenu({
    super.key,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  final List<AppMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: palette.border),
      ),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            child: Text(
              item.label,
              style: theme.typography.body.copyWith(
                color: item.destructive ? palette.danger : palette.text,
              ),
            ),
          ),
      ],
      child: child,
    );
  }
}
