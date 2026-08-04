// Settings — Phase 2 skeleton. Reads settings from the engine on mount;
// write-back is wired in Phase 4.

import 'package:flutter/material.dart';

import '../components/badge.dart';
import '../components/button.dart';
import '../components/card.dart';
import '../components/dropdown.dart';
import '../components/input.dart';
import '../components/switch.dart';
import '../engine/engine_client.dart';
import '../theme/app_theme.dart';
import '../theme/spacing.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? _settings;
  final _historyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _historyCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final client = EngineClient();
    await for (final event in client.run(
      'settings',
      request: {'action': 'get'},
    )) {
      if (event['type'] == 'settings') {
        setState(() {
          _settings = Map<String, dynamic>.from(event['settings'] ?? {});
          _historyCtl.text = '${_settings?['history_limit'] ?? 200}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final settings = _settings;
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Settings', style: theme.typography.pageTitle),
              ),
              const AppBadge(label: 'Engine-owned', tone: BadgeTone.info),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Values persist to the Python JSON stores. Writes ship in Phase 4.',
            style: theme.typography.secondary,
          ),
          const SizedBox(height: 24),
          if (settings == null)
            Text('Loading…', style: theme.typography.secondary)
          else ...[
            _row(
              theme,
              'Default level',
              AppDropdown<String>(
                value: settings['default_level'] as String? ?? 'balanced',
                options: const [
                  DropdownOption('high', 'High quality'),
                  DropdownOption('balanced', 'Balanced'),
                  DropdownOption('maximum', 'Maximum savings'),
                ],
                onChanged: (v) => setState(() => settings['default_level'] = v),
              ),
            ),
            _row(
              theme,
              'Output mode',
              AppDropdown<String>(
                value: settings['output_mode'] as String? ?? 'suffix',
                options: const [
                  DropdownOption('suffix', 'Add suffix'),
                  DropdownOption('directory', 'Output folder'),
                  DropdownOption('overwrite', 'Overwrite'),
                ],
                onChanged: (v) => setState(() => settings['output_mode'] = v),
              ),
            ),
            _row(
              theme,
              'History limit',
              AppInput(
                controller: _historyCtl,
                onChanged: (v) =>
                    settings['history_limit'] = int.tryParse(v) ?? 200,
              ),
            ),
            _switchRow(
              theme,
              'Overwrite confirmation',
              settings['overwrite_confirmation'] == true,
              (v) {
                setState(() => settings['overwrite_confirmation'] = v);
              },
            ),
            _switchRow(
              theme,
              'Add to history',
              settings['add_to_history'] == true,
              (v) {
                setState(() => settings['add_to_history'] = v);
              },
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(label: 'Save', icon: 'check', onPressed: null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(AppTheme theme, String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: Text(label, style: theme.typography.bodyStrong),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    AppTheme theme,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.typography.bodyStrong)),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
