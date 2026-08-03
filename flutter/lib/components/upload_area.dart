// Upload area — drag-target zone. Mirrors components/uploadarea.py.
//
// Drag-and-drop and file dialogs are wired in Phase 3 (needs `file_selector`
// / `desktop_drop` packages). For Phase 2 this is the visual skeleton.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/spacing.dart';
import 'button.dart';

class AppUploadArea extends StatelessWidget {
  const AppUploadArea({
    super.key,
    this.title = 'Drop files here',
    this.subtitle = 'PDF, JPG, PNG, WebP, GIF, BMP, TIFF',
    this.onBrowse,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return DottedBorder(
      color: palette.borderStrong,
      radius: AppRadius.xl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon('upload', size: 32, color: palette.textMuted),
            const SizedBox(height: 12),
            Text(title, style: theme.typography.sectionTitle),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.typography.secondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Choose files',
              icon: 'folder-open',
              variant: ButtonVariant.secondary,
              onPressed: onBrowse,
            ),
          ],
        ),
      ),
    );
  }
}

/// Approximates a CSS "dashed" border. Flutter has no built-in dashed border,
/// so we paint one behind the child. Kept trivial — one uniform corner radius.
class DottedBorder extends StatelessWidget {
  const DottedBorder({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(color: color, radius: radius),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    _drawDashedPath(canvas, path, paint, dashWidth: 6, dashSpace: 4);
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
      old.color != color || old.radius != radius;
}
