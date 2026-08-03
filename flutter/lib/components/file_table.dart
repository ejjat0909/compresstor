// FileTable — the queued-files table shown on the dashboard. Skeleton for
// Phase 2 (columns + row rendering). Behavior (add/remove/select) is wired in
// Phase 3 alongside the engine event stream.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'badge.dart';

enum FileRowStatus { pending, running, done, failed, skipped }

class FileRow {
  const FileRow({
    required this.name,
    required this.kind,
    required this.sizeLabel,
    required this.status,
  });

  final String name;
  final String kind;
  final String sizeLabel;
  final FileRowStatus status;
}

class AppFileTable extends StatelessWidget {
  const AppFileTable({
    super.key,
    required this.rows,
    this.onRemove,
  });

  final List<FileRow> rows;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No files queued',
            style: theme.typography.secondary,
          ),
        ),
      );
    }
    return Column(
      children: [
        _header(theme, palette),
        for (var i = 0; i < rows.length; i++)
          _row(theme, palette, rows[i], i),
      ],
    );
  }

  Widget _header(AppTheme theme, palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Name', style: theme.typography.caption)),
          Expanded(flex: 2, child: Text('Kind', style: theme.typography.caption)),
          Expanded(flex: 2, child: Text('Size', style: theme.typography.caption)),
          Expanded(flex: 2, child: Text('Status', style: theme.typography.caption)),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _row(AppTheme theme, palette, FileRow row, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(row.name, style: theme.typography.body)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppBadge(label: row.kind, tone: BadgeTone.neutral),
            ),
          ),
          Expanded(flex: 2, child: Text(row.sizeLabel, style: theme.typography.secondary)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(row.status),
            ),
          ),
          SizedBox(
            width: 32,
            child: onRemove == null
                ? null
                : IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.close, size: 16, color: palette.textMuted),
                    onPressed: () => onRemove!(index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(FileRowStatus status) {
    switch (status) {
      case FileRowStatus.pending:
        return const AppBadge(label: 'Pending', tone: BadgeTone.neutral);
      case FileRowStatus.running:
        return const AppBadge(label: 'Running', tone: BadgeTone.info);
      case FileRowStatus.done:
        return const AppBadge(label: 'Done', tone: BadgeTone.success);
      case FileRowStatus.failed:
        return const AppBadge(label: 'Failed', tone: BadgeTone.danger);
      case FileRowStatus.skipped:
        return const AppBadge(label: 'Skipped', tone: BadgeTone.warning);
    }
  }
}
