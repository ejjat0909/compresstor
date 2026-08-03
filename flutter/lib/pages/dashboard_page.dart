// Dashboard — Phase 2 skeleton. Uses the shared components to lay out the
// upload area + file table + action bar. Real drag/drop and engine wiring
// come in Phase 3.

import 'package:flutter/material.dart';

import '../components/badge.dart';
import '../components/button.dart';
import '../components/card.dart';
import '../components/dropdown.dart';
import '../components/file_table.dart';
import '../components/progress.dart';
import '../components/toast.dart';
import '../components/upload_area.dart';
import '../theme/app_theme.dart';
import '../theme/spacing.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _rows = <FileRow>[];
  String _level = 'balanced';
  String _outputMode = 'suffix';

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Compress files locally',
                  style: theme.typography.pageTitle,
                ),
              ),
              const AppBadge(label: 'Beta', tone: BadgeTone.accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Add PDFs and images below. Nothing leaves this machine.',
            style: theme.typography.secondary,
          ),
          const SizedBox(height: 24),
          AppUploadArea(
            onBrowse: () =>
                ToastHost.of(context).info('Picker coming in Phase 3'),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: AppFileTable(
              rows: _rows,
              onRemove: (i) => setState(() => _rows.removeAt(i)),
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compression options',
                    style: theme.typography.cardTitle),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _labeled(
                        theme,
                        'Level',
                        AppDropdown<String>(
                          value: _level,
                          options: const [
                            DropdownOption('high', 'High quality'),
                            DropdownOption('balanced', 'Balanced'),
                            DropdownOption('maximum', 'Maximum savings'),
                          ],
                          onChanged: (v) => setState(() => _level = v ?? _level),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _labeled(
                        theme,
                        'Output',
                        AppDropdown<String>(
                          value: _outputMode,
                          options: const [
                            DropdownOption('suffix', 'Add suffix'),
                            DropdownOption('directory', 'Output folder'),
                            DropdownOption('overwrite', 'Overwrite'),
                          ],
                          onChanged: (v) =>
                              setState(() => _outputMode = v ?? _outputMode),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              AppButton(
                label: 'Run compression',
                icon: 'sparkles',
                onPressed: _rows.isEmpty ? null : () {},
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Clear',
                variant: ButtonVariant.outline,
                onPressed:
                    _rows.isEmpty ? null : () => setState(_rows.clear),
              ),
              const Spacer(),
              const SizedBox(
                width: 220,
                child: AppProgress(value: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _labeled(AppTheme theme, String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.typography.caption),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
