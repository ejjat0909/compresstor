// Sidebar — vertical navigation. Mirrors app/presentation/widgets/sidebar.py.

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
    this.updateAvailable = false,
    this.updateVersion,
    this.onUpdateTap,
  });

  static const List<SidebarItem> defaultItems = [
    SidebarItem(id: 'dashboard', label: 'Compress Files', icon: 'gauge'),
    SidebarItem(id: 'history', label: 'History', icon: 'history'),
    SidebarItem(id: 'settings', label: 'Settings', icon: 'settings'),
  ];

  final List<SidebarItem> items;
  final String current;
  final ValueChanged<String> onSelected;
  final bool updateAvailable;
  final String? updateVersion;
  final VoidCallback? onUpdateTap;

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
                Expanded(
                  child: Text(
                    'Compresstor',
                    style: theme.typography.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
          const Spacer(),
          if (updateAvailable) _UpdateBanner(
            version: updateVersion,
            onTap: onUpdateTap,
          ),
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatefulWidget {
  const _UpdateBanner({this.version, this.onTap});
  final String? version;
  final VoidCallback? onTap;

  @override
  State<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<_UpdateBanner> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hover
                ? palette.accent.withValues(alpha: 0.15)
                : palette.accent.withValues(alpha: 0.08),
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: palette.accent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              AppIcon('download', size: 16, color: palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Update available',
                      style: theme.typography.body.copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (widget.version != null)
                      Text(
                        'v${widget.version}',
                        style: theme.typography.caption.copyWith(
                          color: palette.accent.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              AppIcon('chevron-right', size: 14, color: palette.accent),
            ],
          ),
        ),
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
              Expanded(
                child: Text(
                  widget.item.label,
                  style: theme.typography.body.copyWith(
                    color: fg,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
