// Switch — themed on/off toggle. Mirrors components/switch.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.of(context).palette;
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: palette.accent,
      inactiveThumbColor: palette.textSecondary,
      inactiveTrackColor: palette.hover,
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : palette.borderStrong,
      ),
    );
  }
}
