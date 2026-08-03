// Dropdown — themed select. Mirrors QComboBox styling.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';

class DropdownOption<T> {
  const DropdownOption(this.value, this.label);
  final T value;
  final String label;
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.enabled = true,
  });

  final T? value;
  final List<DropdownOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final AppPalette palette = theme.palette;
    return Container(
      decoration: BoxDecoration(
        color: enabled ? palette.input : palette.bg,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          onChanged: enabled ? onChanged : null,
          hint: placeholder == null
              ? null
              : Text(placeholder!, style: theme.typography.body.copyWith(
                  color: palette.textMuted,
                )),
          style: theme.typography.body,
          dropdownColor: palette.card,
          icon: Icon(Icons.expand_more, color: palette.textMuted, size: 18),
          borderRadius: AppRadius.lgAll,
          items: options
              .map((o) => DropdownMenuItem<T>(
                    value: o.value,
                    child: Text(o.label, style: theme.typography.body),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
