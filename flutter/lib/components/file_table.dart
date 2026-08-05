// FileTable — the queued-files table shown on the dashboard. Phase 3 builds
// out the Phase 2 skeleton: row selection (checkboxes + select-all), per-kind
// icons with the file's parent path as secondary text, status badges with
// icons, per-row remove, and a right-click context menu. Rows use compact
// padding and no inner dividers to match the compact-row convention.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';
import 'badge.dart';

enum FileRowStatus { pending, running, done, failed, skipped }

class FileRow {
  const FileRow({
    required this.path,
    required this.name,
    required this.kindLabel,
    required this.kindIcon,
    required this.sizeLabel,
    required this.status,
    this.parent,
  });

  final String path;
  final String name;
  final String kindLabel;
  final String kindIcon;
  final String sizeLabel;
  final FileRowStatus status;
  final String? parent;
}

class AppFileTable extends StatefulWidget {
  const AppFileTable({
    super.key,
    required this.rows,
    this.onRemove,
    this.onSelectionChanged,
    this.onRevealPath,
    this.onCopyPath,
    this.blockedRows = const {},
  });

  final List<FileRow> rows;

  /// Remove one row by its current index (data-space index).
  final ValueChanged<int>? onRemove;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final ValueChanged<String>? onRevealPath;
  final ValueChanged<String>? onCopyPath;

  /// Row indices that shouldn't respond to selection or removal (e.g. running).
  final Set<int> blockedRows;

  @override
  State<AppFileTable> createState() => _AppFileTableState();
}

class _AppFileTableState extends State<AppFileTable> {
  final Set<int> _checked = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    if (widget.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text('No files queued', style: theme.typography.secondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(theme, palette),
        for (var i = 0; i < widget.rows.length; i++)
          _row(theme, palette, widget.rows[i], i),
      ],
    );
  }

  // -------------------------------------------------------------- selection --

  void _toggle(int index) {
    if (widget.blockedRows.contains(index)) return;
    setState(() {
      if (_checked.contains(index)) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    });
    widget.onSelectionChanged?.call(_checked);
  }

  void _toggleAll(bool? checked) {
    final selectable = <int>[
      for (var i = 0; i < widget.rows.length; i++)
        if (!widget.blockedRows.contains(i)) i,
    ];
    setState(() {
      if (checked == true) {
        _checked.addAll(selectable);
      } else {
        _checked.removeAll(selectable);
      }
    });
    widget.onSelectionChanged?.call(_checked);
  }

  bool get _allSelected {
    final selectable = widget.rows.length - widget.blockedRows.length;
    return selectable > 0 && _checked.length >= selectable;
  }

  // ---------------------------------------------------------------- header --

  Widget _header(AppTheme theme, AppPalette palette) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 12, top: 10, bottom: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _allSelected,
            tristate: true,
            onChanged: _toggleAll,
            fillColor: WidgetStateProperty.all(palette.accentSoft),
            checkColor: palette.accent,
            side: BorderSide(color: palette.borderStrong),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: Text('Name', style: theme.typography.caption),
          ),
          Expanded(
            flex: 2,
            child: Text('Kind', style: theme.typography.caption),
          ),
          Expanded(
            flex: 2,
            child: Text('Size', style: theme.typography.caption),
          ),
          Expanded(
            flex: 2,
            child: Text('Status', style: theme.typography.caption),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ rows --

  Widget _row(AppTheme theme, AppPalette palette, FileRow row, int index) {
    final blocked = widget.blockedRows.contains(index);
    final selected = _checked.contains(index);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggle(index),
        onSecondaryTapDown:
            widget.onRevealPath == null && widget.onCopyPath == null
            ? null
            : (d) => _showContextMenu(theme, palette, row, d.globalPosition),
        child: Container(
          padding: const EdgeInsets.only(
            left: 10,
            right: 10,
            top: 4,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.accentSoft.withValues(alpha: 0.1) : null,
            borderRadius: AppRadius.mdAll,
          ),

          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: blocked ? null : (_) => _toggle(index),
                fillColor: WidgetStateProperty.all(palette.accentSoft),
                activeColor: palette.accent,
                checkColor: palette.accentForeground,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    AppIcon(row.kindIcon, size: 16, color: palette.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            row.name,
                            style: theme.typography.body.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (row.parent != null && row.parent!.isNotEmpty)
                            Text(
                              row.parent!,
                              style: theme.typography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(
                    label: row.kindLabel,
                    tone: BadgeTone.neutral,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(row.sizeLabel, style: theme.typography.secondary),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _statusBadge(row.status),
                ),
              ),
              SizedBox(
                width: 32,
                child: widget.onRemove == null || blocked
                    ? null
                    : Tooltip(
                        message: 'Remove',
                        child: InkWell(
                          borderRadius: AppRadius.smAll,
                          onTap: () => widget.onRemove!(index),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: AppIcon(
                              'x',
                              size: 14,
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(
    AppTheme theme,
    AppPalette palette,
    FileRow row,
    Offset global,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final items = <PopupMenuEntry<String>>[
      if (widget.onRevealPath != null)
        PopupMenuItem(
          value: 'reveal',
          child: Row(
            children: [
              AppIcon('folder-open', size: 15, color: palette.text),
              const SizedBox(width: 8),
              Text('Open file location', style: theme.typography.body),
            ],
          ),
        ),
      if (widget.onCopyPath != null)
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              AppIcon('copy', size: 15, color: palette.text),
              const SizedBox(width: 8),
              Text('Copy full path', style: theme.typography.body),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'remove',
        child: Row(
          children: [
            AppIcon('trash-2', size: 15, color: palette.danger),
            const SizedBox(width: 8),
            Text(
              'Remove from queue',
              style: theme.typography.body.copyWith(color: palette.danger),
            ),
          ],
        ),
      ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(global, global),
        Offset.zero & overlay.size,
      ),
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: palette.border),
      ),
      items: items,
    ).then((value) {
      switch (value) {
        case 'reveal':
          widget.onRevealPath?.call(row.path);
          break;
        case 'copy':
          widget.onCopyPath?.call(row.path);
          break;
        case 'remove':
          widget.onRemove?.call(_indexForPath(row.path));
          break;
      }
    });
  }

  int _indexForPath(String path) {
    for (var i = 0; i < widget.rows.length; i++) {
      if (widget.rows[i].path == path) return i;
    }
    return 0;
  }

  Widget _statusBadge(FileRowStatus status) {
    switch (status) {
      case FileRowStatus.pending:
        return const AppBadge(label: 'Pending', tone: BadgeTone.neutral);
      case FileRowStatus.running:
        return const AppBadge(
          label: 'Running…',
          tone: BadgeTone.info,
          icon: _StatusIcon('refresh-cw'),
        );
      case FileRowStatus.done:
        return const AppBadge(
          label: 'Done',
          tone: BadgeTone.success,
          icon: _StatusIcon('circle-check'),
        );
      case FileRowStatus.failed:
        return const AppBadge(
          label: 'Failed',
          tone: BadgeTone.danger,
          icon: _StatusIcon('x'),
        );
      case FileRowStatus.skipped:
        return const AppBadge(
          label: 'Skipped',
          tone: BadgeTone.warning,
          icon: _StatusIcon('info'),
        );
    }
  }
}

/// Small const-friendly icon wrapper for the badge's leading icon slot.
/// Renders with the badge's own foreground color via the parent AppBadge.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    // Parent badge provides spacing; color is resolved by the badge's theme.
    return AppIcon(name, size: 12);
  }
}
