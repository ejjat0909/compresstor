// Upload area — drag-target + file picker. Phase 3 wires the real behaviour:
//   - spawns the OS file dialog via `file_selector` (same accept rules as the
//     Qt app: PDF + images)
//   - accepts OS file drag-and-drop via `desktop_drop`
// The visual skeleton from Phase 2 is kept; only the wiring changed.

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/spacing.dart';
import 'button.dart';

const XTypeGroup _supportedGroup = XTypeGroup(
  label: 'Supported files',
  extensions: [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'gif',
  ],
);

class AppUploadArea extends StatefulWidget {
  const AppUploadArea({
    super.key,
    this.title = 'Drop files here',
    this.subtitle = 'PDF, JPG, PNG, WebP, BMP, TIFF, GIF',
    this.onFilesSelected,
  });

  final String title;
  final String subtitle;

  /// Invoked with the chosen/dropped file paths (with the browser).
  final ValueChanged<List<String>>? onFilesSelected;

  @override
  State<AppUploadArea> createState() => _AppUploadAreaState();
}

class _AppUploadAreaState extends State<AppUploadArea> {
  bool _dragOver = false;

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: const [_supportedGroup]);
    if (files.isEmpty) return;
    widget.onFilesSelected?.call([for (final f in files) f.path]);
  }

  void _handleDropped(DropDoneDetails details) {
    setState(() => _dragOver = false);
    final paths = [for (final f in details.files) f.path];
    if (paths.isNotEmpty) widget.onFilesSelected?.call(paths);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    final borderColor = _dragOver ? palette.accent : palette.borderStrong;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: _handleDropped,
      child: DottedBorder(
        color: borderColor,
        radius: AppRadius.xl,
        active: _dragOver,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: _dragOver
                ? palette.accentSoft.withValues(alpha: 0.6)
                : palette.accent.withValues(alpha: 0.02),
            borderRadius: AppRadius.xlAll,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                'upload',
                size: 32,
                color: _dragOver ? palette.accent : palette.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: theme.typography.sectionTitle.copyWith(
                  color: _dragOver ? palette.accent : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: theme.typography.secondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Choose files',
                icon: 'folder-open',
                variant: ButtonVariant.secondary,
                onPressed: _browse,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Approximates a CSS dashed border, accenting when [active] (drag-over).
class DottedBorder extends StatelessWidget {
  const DottedBorder({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.active = false,
  });

  final Widget child;
  final Color color;
  final double radius;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(
        color: color,
        radius: radius,
        active: active,
        dotColor: AppTheme.of(context).palette.accent.withValues(alpha: 0.35),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({
    required this.color,
    required this.radius,
    required this.active,
    required this.dotColor,
  });
  final Color color;
  final double radius;
  final bool active;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 1.8 : 1.4;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    _drawDashedPath(
      canvas,
      path,
      paint,
      dashWidth: active ? 8 : 6,
      dashSpace: 4,
    );
    if (active) {
      final inner = RRect.fromRectAndRadius(
        Rect.fromLTWH(6, 6, size.width - 12, size.height - 12),
        Radius.circular(radius - 4),
      );
      final innerPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(inner, innerPaint);
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashWidth,
    required double dashSpace,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final extract = metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.active != active ||
      old.dotColor != dotColor;
}
