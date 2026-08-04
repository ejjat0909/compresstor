// History — Phase 2 skeleton. Reads once from the engine on init; wired
// out to full CRUD in Phase 4.

import 'package:flutter/material.dart';

import '../components/badge.dart';
import '../components/button.dart';
import '../components/card.dart';
import '../engine/engine_client.dart';
import '../theme/app_theme.dart';
import '../theme/spacing.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaitedLoad();
  }

  Future<void> unawaitedLoad() async {
    final client = EngineClient();
    await for (final event in client.run(
      'history',
      request: {'action': 'list', 'limit': 200},
    )) {
      if (event['type'] == 'history') {
        setState(() {
          _entries = List<Map<String, dynamic>>.from(event['entries'] ?? []);
          _loading = false;
        });
      } else if (event['type'] == 'error') {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('History', style: theme.typography.pageTitle),
              ),
              AppButton(
                label: 'Refresh',
                icon: 'arrow-right',
                variant: ButtonVariant.outline,
                onPressed: () {
                  setState(() => _loading = true);
                  unawaitedLoad();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _loading
                ? 'Loading…'
                : '${_entries.length} entries from the engine store',
            style: theme.typography.secondary,
          ),
          const SizedBox(height: 20),
          AppCard(
            child: _entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _loading ? 'Loading…' : 'No history yet.',
                        style: theme.typography.secondary,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in _entries.take(50))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: palette.borderSoft),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  '${e['file_name']}',
                                  style: theme.typography.body,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: AppBadge(
                                  label: '${e['kind']}'.toUpperCase(),
                                  tone: BadgeTone.neutral,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatSize(e['compressed_size']),
                                  style: theme.typography.secondary,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: AppBadge(
                                  label: '${e['status']}',
                                  tone: e['status'] == 'done'
                                      ? BadgeTone.success
                                      : BadgeTone.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _formatSize(dynamic bytes) {
    if (bytes is! num) return '';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }
}
