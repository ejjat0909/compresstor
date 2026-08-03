// Sidebar — vertical navigation. Mirrors app/presentation/widgets/sidebar.py.
//
// Compresstor's sidebar has Dashboard / History / Settings. The PySide6 app
// keeps Settings out of the sidebar (it's a route on the top-right), but the
// migration plan asks for all three, so we include Settings here.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/spacing.dart';

class SidebarItem {
  const SidebarItem({required this.id, required this.label, required this.icon});
  final String id;
  final String label;
  final String icon;
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.current,
    required this.onSelected,
  });

  static const List<SidebarItem> defaultItems = [
    SidebarItem(id: 'dashboard', label: 'Dashboard', icon: 'gauge'),
    SidebarItem(id: 'history', label: 'History', icon: 'history'),
    SidebarItem(id: 'settings', label: 'Settings', icon: 'settings'),
  ];

  final List<SidebarItem> items;
  final String current;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                AppIcon('sparkles', size: 20, color: palette.accent),
                const SizedBox(width: 10),
                Text('Compresstor', style: theme.typography.bodyStrong),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            _NavItem(
              item: item,
              selected: item.id == current,
              onTap: () => onSelected(item.id),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    final bg = widget.selected
        ? palette.accentSoft
        : _hover
            ? palette.hover
            : Colors.transparent;
    final fg = widget.selected ? palette.text : palette.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              AppIcon(widget.item.icon, size: 16, color: fg),
              const SizedBox(width: 10),
              Text(
                widget.item.label,
                style: theme.typography.body.copyWith(
                  color: fg,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
