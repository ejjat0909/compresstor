// Input — themed TextField. Mirrors QLineEdit styling in styles.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';

class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    this.controller,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final AppPalette palette = theme.palette;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      obscureText: obscureText,
      style: theme.typography.body,
      cursorColor: palette.accent,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: theme.typography.body.copyWith(color: palette.textMuted),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? palette.input : palette.bg,
        contentPadding: AppSpacing.inputPadding,
        border: _border(palette.border),
        enabledBorder: _border(palette.border),
        focusedBorder: _border(palette.accent, width: 1.5),
        disabledBorder: _border(palette.borderSoft),
        hoverColor: palette.inputHover,
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: BorderSide(color: color, width: width),
      );
}
