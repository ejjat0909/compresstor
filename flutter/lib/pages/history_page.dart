// History — full CRUD page (Phase 4). Lists compression history from the
// engine, shows aggregate stats, per-row actions (open file, copy path,
// remove), and a "Clear history" button with confirmation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/badge.dart';
import '../components/button.dart';
import '../components/card.dart';
import '../components/modal.dart';
import '../components/toast.dart';
import '../engine/format.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/spacing.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _loadScheduled = false;

  AppController get _c => AppScope.of(context);

  void _scheduleLoad() {
    if (_loadScheduled) return;
    final c = _c;
    if (c.historyEntries.isEmpty && !c.isLoadingHistory) {
      _loadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.loadHistory();
      });
    }
  }

  // ---------------------------------------------------------------- stats --

  List<Map<String, dynamic>> get _done =>
      _c.historyEntries.where((e) => e['status'] == 'done').toList();

  int get _totalSaved => _done.fold(0, (s, e) {
    final orig = (e['original_size'] as num?)?.toInt() ?? 0;
    final comp = (e['compressed_size'] as num?)?.toInt() ?? 0;
    return s + (orig - comp).clamp(0, orig);
  });

  double get _avgSavings {
    final d = _done;
    if (d.isEmpty) return 0;
    return d.fold(0.0, (s, e) {
      final pct = (e['savings_percent'] as num?)?.toDouble() ?? 0;
      return s + pct;
    }) / d.length;
  }

  int get _todayCount => _c.historyEntries
      .where((e) => isToday((e['timestamp'] as num?)?.toDouble() ?? 0))
      .length;

  // --------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    _scheduleLoad();
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    final entries = _c.historyEntries;
    final loading = _c.isLoadingHistory;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 28, right: 28, top: 22, bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          _buildStats(theme),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Recent Activity', style: theme.typography.cardTitle),
                    const SizedBox(width: 8),
                    AppBadge(
                      label: '${entries.length}',
                      tone: BadgeTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading && entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('Loading…', style: theme.typography.secondary),
                    ),
                  )
                else if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No history yet. Compress some files to see them here.',
                        style: theme.typography.secondary,
                      ),
                    ),
                  )
                else ...[
                  _tableHeader(theme, palette),
                  for (final e in entries) _tableRow(theme, palette, e),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- header --

  Widget _buildHeader(AppTheme theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('History', style: theme.typography.pageTitle),
              const SizedBox(height: 2),
              Text(
                'Everything you have compressed with Compresstor.',
                style: theme.typography.secondary,
              ),
            ],
          ),
        ),
        AppButton(
          label: 'Refresh',
          icon: 'refresh-cw',
          variant: ButtonVariant.outline,
          size: ButtonSize.sm,
          onPressed: _c.isLoadingHistory ? null : () => _c.loadHistory(),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: 'Clear history',
          icon: 'trash-2',
          variant: ButtonVariant.ghost,
          size: ButtonSize.sm,
          onPressed: _c.historyEntries.isEmpty ? null : _onClear,
        ),
      ],
    );
  }

  // --------------------------------------------------------------- stats --

  Widget _buildStats(AppTheme theme) {
    return AppCard(
      child: Row(
        children: [
          _statBlock(theme, 'FILES', '${_done.length}'),
          const SizedBox(width: 24),
          _statBlock(theme, 'SAVED', formatSize(_totalSaved)),
          const SizedBox(width: 24),
          _statBlock(theme, 'AVG SAVINGS', '${_avgSavings.round()}%'),
          const SizedBox(width: 24),
          _statBlock(theme, 'TODAY', '$_todayCount'),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _statBlock(AppTheme theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.typography.caption),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.typography.pageTitle.copyWith(fontSize: 22),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- table --

  Widget _tableHeader(AppTheme theme, palette) {
    final style = theme.typography.caption;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('File', style: style)),
          Expanded(flex: 2, child: Text('Type', style: style)),
          Expanded(
            flex: 2,
            child: Text('Before', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('After', style: style, textAlign: TextAlign.right),
          ),
          Expanded(flex: 2, child: Text('Saved', style: style)),
          Expanded(flex: 2, child: Text('Date', style: style)),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _tableRow(
    AppTheme theme,
    dynamic palette,
    Map<String, dynamic> entry,
  ) {
    final name = entry['file_name'] as String? ?? '';
    final kind = entry['kind'] as String? ?? '';
    final origSize = (entry['original_size'] as num?)?.toInt() ?? 0;
    final compSize = (entry['compressed_size'] as num?)?.toInt() ?? 0;
    final pct = (entry['savings_percent'] as num?)?.toDouble() ?? 0;
    final status = entry['status'] as String? ?? '';
    final ts = (entry['timestamp'] as num?)?.toDouble() ?? 0;
    final outputPath = entry['output_path'] as String? ?? '';

    final kindTone = kind == 'pdf' ? BadgeTone.neutral : BadgeTone.info;
    final savingsTone = status == 'done'
        ? BadgeTone.success
        : status == 'failed'
            ? BadgeTone.danger
            : BadgeTone.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.borderSoft as Color)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      kind == 'pdf' ? 'file-text' : 'image',
                      size: 14,
                      color: palette.textSecondary as Color,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.typography.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (outputPath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Text(
                      outputPath,
                      style: theme.typography.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: AppBadge(
              label: kind == 'pdf' ? 'PDF' : 'Image',
              tone: kindTone,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatSize(origSize),
              style: theme.typography.secondary,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatSize(compSize),
              style: theme.typography.secondary,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: AppBadge(
              label: '${pct.round()}% smaller',
              tone: savingsTone,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatTimestamp(ts),
              style: theme.typography.secondary,
            ),
          ),
          SizedBox(
            width: 44,
            child: _ActionsMenu(
              onOpenLocation: () => _openLocation(outputPath),
              onCopyPath: () => _copyPath(outputPath),
              onRemove: () => _removeEntry(entry),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- actions --

  void _openLocation(String path) {
    final target = File(path).existsSync()
        ? path
        : File(path).parent.existsSync()
            ? File(path).parent.path
            : Platform.environment['HOME'] ?? '/';
    if (Platform.isMacOS) {
      Process.run('open', ['-R', target]);
    } else if (Platform.isWindows) {
      Process.run('explorer', ['/select,', target]);
    } else {
      Process.run('xdg-open', [File(target).parent.path]);
    }
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ToastHost.of(context).info('Copied', 'Output path copied to clipboard.');
    }
  }

  void _removeEntry(Map<String, dynamic> entry) {
    final ts = (entry['timestamp'] as num?)?.toDouble() ?? 0;
    final op = entry['output_path'] as String? ?? '';
    _c.removeHistoryEntry(timestamp: ts, outputPath: op);
  }

  void _onClear() {
    AppModal.show(
      context,
      title: 'Clear history?',
      body: Text(
        'All compression history will be removed. This cannot be undone.',
        style: AppTheme.of(context).typography.secondary,
      ),
      actions: [
        const CancelButton(),
        AppButton(
          label: 'Clear history',
          variant: ButtonVariant.destructive,
          icon: 'trash-2',
          onPressed: () {
            Navigator.of(context).pop();
            _c.clearHistory();
            ToastHost.of(context).info(
              'History cleared',
              'All compression history has been removed.',
            );
          },
        ),
      ],
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({
    required this.onOpenLocation,
    required this.onCopyPath,
    required this.onRemove,
  });

  final VoidCallback onOpenLocation;
  final VoidCallback onCopyPath;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.of(context).palette;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 18, color: palette.textMuted),
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: palette.border),
      ),
      onSelected: (value) {
        switch (value) {
          case 'open':
            onOpenLocation();
          case 'copy':
            onCopyPath();
          case 'remove':
            onRemove();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              AppIcon('folder-open', size: 14, color: palette.textSecondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Open file location', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              AppIcon('copy', size: 14, color: palette.textSecondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Copy output path', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              AppIcon('trash-2', size: 14, color: palette.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Remove from history',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.danger),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
