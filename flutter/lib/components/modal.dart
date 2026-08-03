// Modal — themed dialog. Mirrors components/modal.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spacing.dart';
import 'button.dart';

class AppModal extends StatelessWidget {
  const AppModal({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.width = 480,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final double width;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget body,
    List<Widget>? actions,
    double width = 480,
  }) {
    final palette = AppTheme.of(context).palette;
    return showDialog<T>(
      context: context,
      barrierColor: palette.overlay,
      builder: (_) => AppModal(
        title: title,
        body: body,
        actions: actions,
        width: width,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: palette.border),
          boxShadow: softShadow(palette),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.typography.sectionTitle),
            const SizedBox(height: 12),
            body,
            if (actions != null) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions!.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions![i],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.label = 'Cancel'});
  final String label;
  @override
  Widget build(BuildContext context) => AppButton(
        label: label,
        variant: ButtonVariant.outline,
        onPressed: () => Navigator.of(context).pop(),
      );
}
