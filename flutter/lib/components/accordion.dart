// Accordion — collapsible sections. Mirrors components/accordion.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/spacing.dart';

class AppAccordion extends StatefulWidget {
  const AppAccordion({
    super.key,
    required this.title,
    required this.body,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget body;
  final bool initiallyOpen;

  @override
  State<AppAccordion> createState() => _AppAccordionState();
}

class _AppAccordionState extends State<AppAccordion> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: AppRadius.lgAll,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: theme.typography.bodyStrong),
                  ),
                  AppIcon(
                    _open ? 'chevron-down' : 'chevron-right',
                    size: 14,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 14),
              child: widget.body,
            ),
        ],
      ),
    );
  }
}
