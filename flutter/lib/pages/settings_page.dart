// Settings — Phase 4: full read/write parity with the PySide6 settings page.
// Appearance (accent color swatches), compression defaults (level, output mode,
// output folder browse, suffix), behaviour toggles, about card, Save + Reset.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../components/button.dart';
import '../components/card.dart';
import '../components/dropdown.dart';
import '../components/input.dart';
import '../components/progress.dart';
import '../components/switch.dart';
import '../components/toast.dart';
import '../engine/models.dart';
import '../engine/update_applier_macos.dart';
import '../engine/update_applier_windows.dart';
import '../engine/update_client.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import '../state/update_controller.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/spacing.dart';

const _accentPresets = <(String, String)>[
  ('Blue', '#2563eb'),
  ('Indigo', '#4f46e5'),
  ('Violet', '#7c3aed'),
  ('Emerald', '#059669'),
  ('Rose', '#e11d48'),
  ('Amber', '#d97706'),
  ('Sky', '#0284c7'),
  ('Slate', '#475569'),
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.updateController});

  /// Injectable for tests; when null the page owns a real controller
  /// (GitHub Releases transport + the platform applier).
  final UpdateController? updateController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _historyCtl = TextEditingController();
  final _suffixCtl = TextEditingController(text: '_compressed');
  final _folderCtl = TextEditingController();

  String _accentColor = '#3b82f6';
  String _defaultLevel = 'balanced';
  String _outputMode = 'suffix';
  bool _overwriteConfirmation = true;
  bool _addToHistory = true;
  int _historyLimit = 200;
  bool _initialized = false;

  AppController? _prev;

  late final UpdateController _update;
  late final bool _ownsUpdate;
  UpdateStatus _lastUpdateStatus = UpdateStatus.idle;

  @override
  void initState() {
    super.initState();
    _ownsUpdate = widget.updateController == null;
    _update = widget.updateController ?? _defaultUpdateController();
    _update.addListener(_onUpdateChanged);
    if (_ownsUpdate) {
      _update.loadVersion(); // async — the About card rebuilds when it lands
    }
  }

  UpdateController _defaultUpdateController() {
    final isWindows = UpdateClient.defaultUpdatePlatform() == 'windows';
    return UpdateController(
      client: UpdateClient(),
      applier: isWindows ? WindowsUpdateApplier() : MacOsUpdateApplier(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AppScope.of(context);
    if (!identical(_prev, c)) {
      _prev?.removeListener(_tick);
      _prev = c;
      c.addListener(_tick);
    }
    _loadFromController(c);
  }

  void _loadFromController(AppController c) {
    if (_initialized || c.isLoadingSettings) return;
    final s = c.settings;
    _initialized = true;
    _accentColor = s.accentColor;
    _defaultLevel = s.defaultLevel;
    _outputMode = s.outputMode;
    _folderCtl.text = s.outputDir;
    _overwriteConfirmation = s.overwriteConfirmation;
    _addToHistory = s.addToHistory;
    _historyLimit = s.historyLimit;
    _historyCtl.text = '$_historyLimit';
  }

  @override
  void dispose() {
    _prev?.removeListener(_tick);
    _update.removeListener(_onUpdateChanged);
    if (_ownsUpdate) {
      _update.dispose();
    }
    _historyCtl.dispose();
    _suffixCtl.dispose();
    _folderCtl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    _loadFromController(_prev!);
    setState(() {});
  }

  /// Fires toasts on update-state transitions (once per transition).
  void _onUpdateChanged() {
    if (!mounted) return;
    final s = _update.status;
    if (s == UpdateStatus.upToDate && _lastUpdateStatus != UpdateStatus.upToDate) {
      ToastHost.of(context).success(
        'You\u2019re up to date',
        'You\u2019re running the latest version '
            '(${_update.currentVersion}).',
      );
    } else if (s == UpdateStatus.error &&
        _lastUpdateStatus != UpdateStatus.error) {
      if (_update.manifest == null) {
        ToastHost.of(context).danger(
          'Couldn\u2019t check for updates',
          _update.error ?? 'Something went wrong.',
        );
      } else {
        ToastHost.of(context).danger(
          'Update failed',
          _update.error ?? 'Something went wrong.',
        );
      }
    }
    _lastUpdateStatus = s;
  }

  AppController get _c => _prev ?? AppScope.of(context);

  // --------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 28, right: 28, top: 22, bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: theme.typography.pageTitle),
          const SizedBox(height: 2),
          Text(
            'Personalize Compresstor and set your default compression behaviour.',
            style: theme.typography.secondary,
          ),
          const SizedBox(height: 24),
          _buildAppearanceCard(theme),
          const SizedBox(height: 16),
          _buildDefaultsCard(theme),
          const SizedBox(height: 16),
          _buildAboutCard(theme),
          const SizedBox(height: 20),
          _buildActions(theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- appearance --

  Widget _buildAppearanceCard(AppTheme theme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: theme.typography.cardTitle),
          const SizedBox(height: 16),
          Text('ACCENT COLOR', style: theme.typography.caption),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (name, hex) in _accentPresets)
                _AccentSwatch(
                  color: hex,
                  selected: _accentColor.toLowerCase() == hex.toLowerCase(),
                  tooltip: name,
                  onTap: () => _setAccent(hex),
                ),
              _CustomColorButton(
                currentColor: _accentColor,
                onColorPicked: _setAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setAccent(String hex) {
    setState(() => _accentColor = hex);
  }

  // ------------------------------------------------------------ defaults --

  Widget _buildDefaultsCard(AppTheme theme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compression Defaults', style: theme.typography.cardTitle),
          const SizedBox(height: 16),
          Text('DEFAULT LEVEL', style: theme.typography.caption),
          const SizedBox(height: 6),
          AppDropdown<String>(
            value: _defaultLevel,
            options: const [
              DropdownOption('high', 'High — best quality'),
              DropdownOption('balanced', 'Balanced — recommended'),
              DropdownOption('maximum', 'Maximum — smallest size'),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _defaultLevel = v);
            },
          ),
          const SizedBox(height: 16),
          Text('OUTPUT', style: theme.typography.caption),
          const SizedBox(height: 6),
          AppDropdown<String>(
            value: _outputMode,
            options: const [
              DropdownOption('suffix', 'Next to original — new file'),
              DropdownOption('directory', 'Into a chosen folder'),
              DropdownOption('overwrite', 'Replace original file'),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _outputMode = v);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppInput(
                  controller: _folderCtl,
                  placeholder: 'Default output folder…',
                  enabled: false,
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Browse…',
                icon: 'folder',
                variant: ButtonVariant.secondary,
                size: ButtonSize.sm,
                onPressed: _pickFolder,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('BEHAVIOUR', style: theme.typography.caption),
          const SizedBox(height: 8),
          _switchRow(
            theme,
            'Add results to history',
            _addToHistory,
            (v) => setState(() => _addToHistory = v),
          ),
          _switchRow(
            theme,
            'Confirm before overwriting',
            _overwriteConfirmation,
            (v) => setState(() => _overwriteConfirmation = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 200,
                child: Text(
                  'History limit',
                  style: theme.typography.bodyStrong,
                ),
              ),
              SizedBox(
                width: 100,
                child: AppInput(
                  controller: _historyCtl,
                  onChanged: (v) =>
                      _historyLimit = int.tryParse(v) ?? _historyLimit,
                ),
              ),
            ],
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.typography.bodyStrong)),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath(
      confirmButtonText: 'Choose',
    );
    if (dir != null) {
      setState(() => _folderCtl.text = dir);
    }
  }

  // --------------------------------------------------------------- about --

  Widget _buildAboutCard(AppTheme theme) {
    return AppCard(
      child: ListenableBuilder(
        listenable: _update,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About', style: theme.typography.cardTitle),
              const SizedBox(height: 8),
              Text('Compresstor', style: theme.typography.bodyStrong),
              const SizedBox(height: 2),
              Text(
                'Version ${_update.currentVersion}',
                style: theme.typography.body,
              ),
              const SizedBox(height: 4),
              Text(
                'Compresses PDF and image files entirely on your device. '
                'Files never leave your computer.',
                style: theme.typography.caption,
              ),
              const SizedBox(height: 14),
              _buildUpdateSection(theme),
            ],
          );
        },
      ),
    );
  }

  /// Status-driven update controls: Check -> spinner -> up-to-date caption /
  /// "Update available" row -> download progress -> install -> back to Check.
  Widget _buildUpdateSection(AppTheme theme) {
    final u = _update;
    final Widget child;
    switch (u.status) {
      case UpdateStatus.checking:
        child = Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(theme.palette.textSecondary),
              ),
            ),
            const SizedBox(width: 10),
            Text('Checking for updates\u2026', style: theme.typography.caption),
          ],
        );
      case UpdateStatus.upToDate:
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon('circle-check', size: 14, color: theme.palette.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'You\u2019re running the latest version '
                        '(${u.currentVersion}).',
                    style: theme.typography.caption,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Check for updates',
              icon: 'refresh-cw',
              variant: ButtonVariant.ghost,
              size: ButtonSize.sm,
              onPressed: u.checkForUpdates,
            ),
          ],
        );
      case UpdateStatus.updateAvailable:
        final m = u.manifest!;
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${m.version} is available',
              style: theme.typography.bodyStrong,
            ),
            if (m.notes.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                m.notes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption,
              ),
            ],
            const SizedBox(height: 10),
            AppButton(
              label: 'Update',
              icon: 'download',
              variant: ButtonVariant.primary,
              size: ButtonSize.sm,
              onPressed: u.update,
            ),
          ],
        );
      case UpdateStatus.downloading:
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppProgress(value: u.progress),
            const SizedBox(height: 6),
            Text(
              'Downloading\u2026 ${(u.progress * 100).round()}%',
              style: theme.typography.caption,
            ),
          ],
        );
      case UpdateStatus.applying:
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppProgress(),
            const SizedBox(height: 6),
            Text(
              'Installing\u2026 the app will restart.',
              style: theme.typography.caption,
            ),
          ],
        );
      case UpdateStatus.error:
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              u.error ?? 'Something went wrong.',
              style: theme.typography.caption.copyWith(
                color: theme.palette.danger,
              ),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: u.manifest != null ? 'Update' : 'Check for updates',
              icon: u.manifest != null ? 'download' : 'refresh-cw',
              variant:
                  u.manifest != null ? ButtonVariant.primary : ButtonVariant.ghost,
              size: ButtonSize.sm,
              onPressed: u.manifest != null ? u.update : u.checkForUpdates,
            ),
          ],
        );
      case UpdateStatus.idle:
      case UpdateStatus.relaunched:
        child = AppButton(
          label: 'Check for updates',
          icon: 'refresh-cw',
          variant: ButtonVariant.ghost,
          size: ButtonSize.sm,
          onPressed: u.checkForUpdates,
        );
    }
    return child;
  }

  // ------------------------------------------------------------- actions --

  Widget _buildActions(AppTheme theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          label: 'Reset to defaults',
          icon: 'rotate-ccw',
          variant: ButtonVariant.ghost,
          onPressed: _onReset,
        ),
        const SizedBox(width: 8),
        AppButton(
          label: 'Save settings',
          icon: 'save',
          variant: ButtonVariant.primary,
          onPressed: _onSave,
        ),
      ],
    );
  }

  AppSettings _collect() {
    return AppSettings(
      accentColor: _accentColor,
      historyLimit: _historyLimit,
      defaultLevel: _defaultLevel,
      outputMode: _outputMode,
      outputDir: _folderCtl.text,
      overwriteConfirmation: _overwriteConfirmation,
      addToHistory: _addToHistory,
    );
  }

  void _onSave() {
    _c.saveSettings(_collect());
    ToastHost.of(context).success(
      'Settings saved',
      'Your preferences have been updated.',
    );
  }

  void _onReset() {
    const fresh = AppSettings();
    setState(() {
      _accentColor = fresh.accentColor;
      _defaultLevel = fresh.defaultLevel;
      _outputMode = fresh.outputMode;
      _folderCtl.text = fresh.outputDir;
      _overwriteConfirmation = fresh.overwriteConfirmation;
      _addToHistory = fresh.addToHistory;
      _historyLimit = fresh.historyLimit;
      _historyCtl.text = '${fresh.historyLimit}';
    });
    _c.saveSettings(fresh);
    ToastHost.of(context).info(
      'Settings reset',
      'All settings restored to defaults.',
    );
  }
}

// ----------------------------------------------------------- accent swatch --

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final String color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parsed = _parseHex(color);
    final palette = AppTheme.of(context).palette;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: parsed,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({
    required this.currentColor,
    required this.onColorPicked,
  });

  final String currentColor;
  final ValueChanged<String> onColorPicked;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Custom…',
      icon: 'palette',
      variant: ButtonVariant.outline,
      size: ButtonSize.sm,
      onPressed: () => _pickColor(context),
    );
  }

  Future<void> _pickColor(BuildContext context) async {
    final palette = AppTheme.of(context).palette;
    final controller = TextEditingController(text: currentColor);
    final result = await showDialog<String>(
      context: context,
      barrierColor: palette.overlay,
      builder: (ctx) => _ColorPickerDialog(
        controller: controller,
        initialColor: currentColor,
      ),
    );
    controller.dispose();
    if (result != null) {
      onColorPicked(result);
    }
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.controller,
    required this.initialColor,
  });
  final TextEditingController controller;
  final String initialColor;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late String _hex;

  @override
  void initState() {
    super.initState();
    _hex = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Custom accent color', style: theme.typography.cardTitle),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _parseHex(_hex),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: palette.border),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppInput(
                    controller: widget.controller,
                    placeholder: '#hex',
                    onChanged: (v) {
                      if (v.startsWith('#') && (v.length == 7 || v.length == 4)) {
                        setState(() => _hex = v);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: ButtonVariant.outline,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Apply',
                  variant: ButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(_hex),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _parseHex(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length == 3) {
    final r = clean[0], g = clean[1], b = clean[2];
    return Color(int.parse('FF$r$r$g$g$b$b', radix: 16));
  }
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return const Color(0xFF3B82F6);
}
