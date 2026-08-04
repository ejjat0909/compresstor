// Dashboard — the compression work surface (Phase 3).
//
// Ports app/presentation/pages/dashboard_page.py: header + upload area, a
// two-column layout (file queue + compression settings), drag-and-drop / file
// picker, per-file queue with statuses, compression options (level presets,
// output mode, suffix, max-size target, advanced accordion), and the
// progress → summary modal flow driven by engine events.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/accordion.dart';
import '../components/badge.dart';
import '../components/button.dart';
import '../components/card.dart';
import '../components/dropdown.dart';
import '../components/file_table.dart';
import '../components/input.dart';
import '../components/progress.dart';
import '../components/switch.dart';
import '../components/toast.dart';
import '../components/upload_area.dart';
import '../engine/format.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';

const Map<CompressionLevel, (String, String)> _levelMeta = {
  CompressionLevel.high: ('High', 'Best quality, modest savings'),
  CompressionLevel.balanced: ('Balanced', 'Great quality, good savings'),
  CompressionLevel.maximum: ('Maximum', 'Smallest size, some quality loss'),
};

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.controller});
  final AppController? controller;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // form state
  CompressionLevel _level = CompressionLevel.balanced;
  OutputMode _mode = OutputMode.suffix;
  final _suffixCtrl = TextEditingController(text: '_compressed');
  final _maxCtrl = TextEditingController();
  final _folderCtrl = TextEditingController();
  int _pdfQuality = 70;
  int _maxDpi = 144;
  int _imgQuality = 72;
  int _maxDim = 0;
  bool _stripMeta = true;
  bool _keepFormat = true;

  Set<int> _selected = <int>{};
  bool _initialized = false;
  bool _wasRunning = false;
  bool _toastShown = true;
  AppController? _prev;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.controller ?? AppScope.of(context);
    if (!identical(_prev, c)) {
      _prev?.removeListener(_onControllerTick);
      _prev = c;
      c.addListener(_onControllerTick);
    }
  }

  @override
  void dispose() {
    _prev?.removeListener(_onControllerTick);
    _suffixCtrl.dispose();
    _maxCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  void _onControllerTick() {
    if (!mounted || _prev == null) return;
    final c = _prev!;
    if (!c.isLoadingSettings && !_initialized) {
      _initialized = true;
      _level = c.settings.defaultCompressionLevel;
      _mode = c.settings.defaultOutputMode;
      _folderCtrl.text = c.settings.outputDir;
      setState(() {});
    }
    if (c.running && !_wasRunning) {
      _wasRunning = true;
      _toastShown = false;
    }
    if (!c.running && _wasRunning) {
      _wasRunning = false;
      if (mounted && !_toastShown) {
        _toastShown = true;
        _showRunToasts(c);
      }
    }
  }

  void _showRunToasts(AppController c) {
    final toasts = ToastHost.of(context);
    if (c.lastCancelled) {
      toasts.info(
        'Compression cancelled',
        'The remaining files in the queue were not processed.',
      );
      return;
    }
    if (c.lastError != null) {
      toasts.danger('Compression failed', c.lastError);
      return;
    }
    final results = c.lastResults ?? const <JobResult>[];
    final done = results.where((r) => r.status == JobStatus.done).toList();
    final failed = results.where((r) => r.status == JobStatus.failed).toList();
    final skipped = results
        .where((r) => r.status == JobStatus.skipped)
        .toList();
    if (done.isNotEmpty) {
      final saved = done.fold(0, (s, r) => s + r.savings);
      final avg = done.fold(0.0, (s, r) => s + r.savingsPercent) / done.length;
      toasts.success(
        'Compression complete',
        '${done.length} file(s) compressed · ${formatSize(saved)} saved · '
            '${avg.round()}% smaller on average.',
      );
    }
    if (failed.isNotEmpty) {
      toasts.danger(
        'Some files failed',
        '${failed.length} file(s) could not be compressed.',
      );
    }
    if (skipped.isNotEmpty) {
      toasts.info(
        'Files skipped',
        '${skipped.length} file(s) were already optimized.',
      );
    }
  }

  AppController get _controller => _prev ?? AppScope.of(context);

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 28, right: 28, top: 22, bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          AppUploadArea(onFilesSelected: _onFilesSelected),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildQueueCard(theme)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildSettingsCard(theme)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- header --

  Widget _buildHeader(AppTheme theme) {
    final c = _controller;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Compress Files', style: theme.typography.pageTitle),
              const SizedBox(height: 2),
              Text(
                'Reduce.  PDF and image file sizes — fast, private and fully local.',
                style: theme.typography.secondary,
              ),
            ],
          ),
        ),
        AppButton(
          label: 'Clear queue',
          variant: ButtonVariant.ghost,
          size: ButtonSize.sm,
          icon: 'trash-2',
          onPressed: c.queue.isEmpty || c.running ? null : c.clearQueue,
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- queue --

  Widget _buildQueueCard(AppTheme theme) {
    final c = _controller;
    final rows = [for (var i = 0; i < c.queue.length; i++) _rowFor(c, i)];
    final blocked = c.running
        ? <int>{for (var i = 0; i < rows.length; i++) i}
        : <int>{};
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Selected Files', style: theme.typography.cardTitle),
          const SizedBox(height: 12),
          AppFileTable(
            rows: rows,
            onRemove: c.running ? null : (i) => c.removeItems([i]),
            onCopyPath: c.running ? null : _copyPath,
            onRevealPath: c.running ? null : _revealInFolder,
            onSelectionChanged: (sel) =>
                setState(() => _selected = Set.of(sel)),
            blockedRows: blocked,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _selected.isEmpty ? '' : '${_selected.length} selected',
                style: theme.typography.caption,
              ),
              const Spacer(),
              AppButton(
                label: 'Remove selected',
                variant: ButtonVariant.secondary,
                size: ButtonSize.sm,
                icon: 'x',
                onPressed: _selected.isEmpty || c.running
                    ? null
                    : () {
                        c.removeItems(_selected.toList());
                        setState(() => _selected.clear());
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  FileRow _rowFor(AppController c, int index) {
    final item = c.queue[index];
    final status = switch (c.statusFor(item.path)) {
      JobStatus.pending => FileRowStatus.pending,
      JobStatus.running => FileRowStatus.running,
      JobStatus.done => FileRowStatus.done,
      JobStatus.failed => FileRowStatus.failed,
      JobStatus.skipped => FileRowStatus.skipped,
    };
    final isPdf = item.kind == FileKind.pdf;
    return FileRow(
      path: item.path,
      name: item.name,
      kindLabel: isPdf ? 'PDF' : 'Image',
      kindIcon: isPdf ? 'file-text' : 'image',
      sizeLabel: formatSize(item.size),
      status: status,
      parent: item.parentDir,
    );
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    ToastHost.of(context).info('Path copied', path);
  }

  void _revealInFolder(String path) {
    final dir = File(path).parent.path;
    if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path]);
    } else {
      Process.run('xdg-open', [dir]);
    }
  }

  // ---------------------------------------------------------------- files --

  void _onFilesSelected(List<String> paths) {
    final c = _controller;
    final result = c.addPaths(paths);
    final toasts = ToastHost.of(context);
    if (result.unsupported.isNotEmpty) {
      toasts.warning(
        'Unsupported files skipped',
        '${result.unsupported.length} file(s) are not PDF or image files.',
      );
    }
    if (result.added.isNotEmpty) {
      toasts.success(
        'Files added',
        '${result.added.length} file(s) added to the queue '
            '(${formatSize(c.totalSize)} total).',
      );
    }
  }

  // -------------------------------------------------------------- settings --

  Widget _buildSettingsCard(AppTheme theme) {
    final c = _controller;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Compression Settings', style: theme.typography.cardTitle),
          const SizedBox(height: 12),
          _caption('COMPRESSION LEVEL'),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final lvl in CompressionLevel.values) ...[
                if (lvl != CompressionLevel.high) const SizedBox(width: 8),
                Expanded(
                  child: _LevelCard(
                    level: lvl,
                    selected: _level == lvl,
                    onTap: () => _selectLevel(lvl),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _caption('OUTPUT'),
          const SizedBox(height: 6),
          AppDropdown<String>(
            value: _mode.name,
            options: const [
              DropdownOption('suffix', 'Next to original — new file'),
              DropdownOption('directory', 'Into a chosen folder'),
              DropdownOption('overwrite', 'Replace original file'),
            ],
            onChanged: (v) => setState(() {
              _mode = OutputMode.values.firstWhere((m) => m.name == v);
            }),
          ),
          if (_mode == OutputMode.suffix) ...[
            const SizedBox(height: 10),
            _field('Suffix', AppInput(controller: _suffixCtrl)),
          ],
          const SizedBox(height: 10),
          _field(
            'Max size (MB)',
            AppInput(controller: _maxCtrl, placeholder: 'Optional — e.g. 5'),
            hint:
                'Compressed files will be this size or below. '
                'Leave empty for automatic.',
          ),
          if (_mode == OutputMode.directory) ...[
            const SizedBox(height: 10),
            _caption('OUTPUT FOLDER'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: AppInput(
                    controller: _folderCtrl,
                    placeholder: 'Choose output folder…',
                    enabled: false,
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Browse…',
                  variant: ButtonVariant.secondary,
                  size: ButtonSize.sm,
                  icon: 'folder',
                  onPressed: _pickFolder,
                ),
              ],
            ),
          ],
          if (_mode == OutputMode.overwrite)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'The original file will be replaced. A backup is not created.',
                style: theme.typography.caption.copyWith(
                  color: theme.palette.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 12),
          AppAccordion(title: 'Advanced options', body: _buildAdvanced(theme)),
          const SizedBox(height: 12),
          AppButton(
            label: 'Compress Files',
            icon: 'zap',
            size: ButtonSize.lg,
            onPressed: c.queue.isEmpty || c.running ? null : _onCompress,
          ),
        ],
      ),
    );
  }

  void _selectLevel(CompressionLevel level) {
    setState(() {
      _level = level;
      final preset = levelPresets[level]!;
      _pdfQuality = preset.pdf.imageQuality;
      _maxDpi = preset.pdf.maxImageDpi;
      _imgQuality = preset.image.quality;
    });
  }

  Widget _buildAdvanced(AppTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sliderRow('PDF image quality', 30, 95, _pdfQuality, (v) {
          setState(() => _pdfQuality = v);
        }),
        _sliderRow('Max PDF image DPI', 72, 300, _maxDpi, (v) {
          setState(() => _maxDpi = v);
        }),
        _sliderRow('Image quality', 30, 95, _imgQuality, (v) {
          setState(() => _imgQuality = v);
        }),
        _stepperRow(
          label: 'Max dimension (px, 0 = original)',
          min: 0,
          max: 10000,
          value: _maxDim,
          step: 100,
          onChanged: (v) => setState(() => _maxDim = v),
        ),
        _switchRow('Strip metadata', _stripMeta, (v) {
          setState(() => _stripMeta = v);
        }),
        _switchRow('Keep original format', _keepFormat, (v) {
          setState(() => _keepFormat = v);
        }),
      ],
    );
  }

  Widget _sliderRow(
    String label,
    int min,
    int max,
    int value,
    ValueChanged<int> onChanged,
  ) {
    final theme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: theme.typography.caption),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              style: theme.typography.caption,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperRow({
    required String label,
    required int min,
    required int max,
    required int value,
    required int step,
    required ValueChanged<int> onChanged,
  }) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.typography.caption)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepButton(
                icon: Icons.remove,
                enabled: value > min,
                onTap: () => onChanged((value - step).clamp(min, max)),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$value',
                  style: theme.typography.body.copyWith(
                    color: palette.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              _stepButton(
                icon: Icons.add,
                enabled: value < max,
                onTap: () => onChanged((value + step).clamp(min, max)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final palette = AppTheme.of(context).palette;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? palette.textSecondary : palette.border,
        ),
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    final theme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.typography.caption)),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- helpers --

  Widget _caption(String text) {
    final theme = AppTheme.of(context);
    return Text(
      text,
      style: theme.typography.caption.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.palette.textSecondary,
      ),
    );
  }

  Widget _field(String label, Widget child, {String? hint}) {
    final theme = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.typography.caption),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: theme.typography.caption),
        ],
      ],
    );
  }

  // --------------------------------------------------------------- actions --

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath(
      initialDirectory: _folderCtrl.text.isEmpty ? null : _folderCtrl.text,
    );
    if (dir != null) setState(() => _folderCtrl.text = dir);
  }

  void _onCompress() {
    final c = _controller;
    final items = List.of(c.queue);
    final toasts = ToastHost.of(context);
    if (items.isEmpty) {
      toasts.warning('Nothing to compress', 'Add files to the queue first.');
      return;
    }

    double? maxMb;
    final raw = _maxCtrl.text.trim();
    if (raw.isNotEmpty) {
      maxMb = double.tryParse(raw);
      if (maxMb == null || maxMb <= 0) {
        toasts.danger(
          'Invalid target size',
          'Enter a valid max size in MB (e.g. 5).',
        );
        return;
      }
      final target = (maxMb * 1024 * 1024).round();
      final offender = items.where((i) => i.size <= target).toList();
      if (offender.isNotEmpty) {
        final names = offender
            .take(3)
            .map((i) => '${i.name} (${formatSize(i.size)})')
            .join(', ');
        final more = offender.length > 3
            ? ' and ${offender.length - 3} more'
            : '';
        toasts.danger(
          'Target size is not smaller',
          '$names$more — set the max size below the original file size.',
        );
        return;
      }
    }

    final options = CompressionOptions(
      level: _level,
      outputMode: _mode,
      outputDir: _mode == OutputMode.directory ? _folderCtrl.text.trim() : '',
      suffix: _suffixCtrl.text.trim().isEmpty
          ? '_compressed'
          : _suffixCtrl.text.trim(),
      maxSizeMb: maxMb,
      pdf: PdfOptions(imageQuality: _pdfQuality, maxImageDpi: _maxDpi),
      image: ImageOptions(
        quality: _imgQuality,
        resizeMax: _maxDim,
        preserveFormat: _keepFormat,
        stripMetadata: _stripMeta,
      ),
    );

    if (_mode == OutputMode.overwrite && c.settings.overwriteConfirmation) {
      _confirmOverwrite(items.length, options);
      return;
    }
    _startRun(items, options);
  }

  void _confirmOverwrite(int count, CompressionOptions options) {
    final palette = AppTheme.of(context).palette;
    showDialog<void>(
      context: context,
      barrierColor: palette.overlay,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
        title: const Text('Replace original files?'),
        content: Text(
          '$count file(s) will be overwritten in place. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _startRun(List.of(_controller.queue), options);
            },
            child: Text(
              'Replace files',
              style: TextStyle(color: palette.danger),
            ),
          ),
        ],
      ),
    );
  }

  void _startRun(List<FileItem> items, CompressionOptions options) {
    _controller.startCompression(items, options);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressRunDialog(controller: _controller),
    );
  }
}

// ================================================================ level card =

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });
  final CompressionLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, desc) = _levelMeta[level]!;
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : palette.card,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.typography.body.copyWith(
                fontWeight: FontWeight.bold,
                color: selected ? palette.accent : palette.text,
              ),
            ),
            Text(
              desc,
              style: theme.typography.caption.copyWith(
                color: selected ? palette.accent : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================== progress run modal =

class _ProgressRunDialog extends StatelessWidget {
  const _ProgressRunDialog({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Container(
            width: 480,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: AppRadius.xlAll,
              border: Border.all(color: palette.border),
              boxShadow: softShadow(palette),
            ),
            child: controller.running
                ? _buildRunning(theme, palette)
                : _buildSummary(theme, palette, context),
          );
        },
      ),
    );
  }

  Widget _buildRunning(AppTheme theme, AppPalette palette) {
    final fraction = controller.progressFraction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compressing files', style: theme.typography.sectionTitle),
        const SizedBox(height: 12),
        Text(
          controller.progressMessage.isNotEmpty
              ? controller.progressMessage
              : '0 of ${controller.runTotal} files',
          style: theme.typography.body,
        ),
        const SizedBox(height: 10),
        AppProgress(value: fraction),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${(fraction * 100).round()}%',
              style: theme.typography.caption,
            ),
            const Spacer(),
            AppButton(
              label: controller.cancelling ? 'Cancelling…' : 'Cancel',
              variant: ButtonVariant.outline,
              size: ButtonSize.sm,
              icon: 'x',
              loading: controller.cancelling,
              onPressed: controller.cancelling
                  ? null
                  : controller.cancelCompression,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary(
    AppTheme theme,
    AppPalette palette,
    BuildContext dialogContext,
  ) {
    final cancelled = controller.lastCancelled;
    final error = controller.lastError;
    final results = controller.lastResults ?? const <JobResult>[];
    final done = results.where((r) => r.status == JobStatus.done).toList();
    final failed = results.where((r) => r.status == JobStatus.failed).toList();
    final skipped = results
        .where((r) => r.status == JobStatus.skipped)
        .toList();

    final String icon;
    final Color iconColor;
    final String title;
    if (cancelled) {
      icon = 'info';
      iconColor = palette.warning;
      title = 'Compression cancelled';
    } else if (error != null) {
      icon = 'x';
      iconColor = palette.danger;
      title = 'Compression failed';
    } else if (done.isNotEmpty) {
      icon = 'circle-check';
      iconColor = palette.success;
      title = 'Compression complete';
    } else if (failed.isNotEmpty) {
      icon = 'x';
      iconColor = palette.danger;
      title = 'Compression failed';
    } else {
      icon = 'info';
      iconColor = palette.info;
      title = 'Nothing to do';
    }

    final String? bodyText;
    final List<Widget> badges = [];
    if (done.isNotEmpty) {
      final saved = done.fold(0, (s, r) => s + r.savings);
      final avg = done.fold(0.0, (s, r) => s + r.savingsPercent) / done.length;
      bodyText =
          '${done.length} file(s) compressed · ${formatSize(saved)} saved · '
          '${avg.round()}% smaller on average.';
      badges.add(
        AppBadge(
          label: '${formatSize(saved)} saved',
          tone: BadgeTone.success,
          icon: const AppIcon('trending-down', size: 12),
        ),
      );
      badges.add(
        AppBadge(
          label: '${avg.round()}% smaller',
          tone: BadgeTone.info,
          icon: const AppIcon('percent', size: 12),
        ),
      );
      if (failed.isNotEmpty) {
        badges.add(
          AppBadge(
            label: '${failed.length} failed',
            tone: BadgeTone.danger,
            icon: const AppIcon('x', size: 12),
          ),
        );
      }
      if (skipped.isNotEmpty) {
        badges.add(
          AppBadge(
            label: '${skipped.length} skipped',
            tone: BadgeTone.warning,
            icon: const AppIcon('info', size: 12),
          ),
        );
      }
    } else if (failed.isNotEmpty) {
      bodyText = '${failed.length} file(s) could not be compressed.';
    } else if (skipped.isNotEmpty) {
      bodyText = '${skipped.length} file(s) were already optimized.';
    } else if (error != null) {
      bodyText = error;
    } else if (cancelled) {
      bodyText = 'The run was cancelled before any results were produced.';
    } else {
      bodyText = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(icon, size: 26, color: iconColor),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: theme.typography.sectionTitle)),
          ],
        ),
        const SizedBox(height: 10),
        if (bodyText != null) Text(bodyText, style: theme.typography.body),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: badges),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Done',
              size: ButtonSize.sm,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
