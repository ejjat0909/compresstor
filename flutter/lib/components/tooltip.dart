// Tooltip — thin wrapper over Material's Tooltip pre-styled via ThemeData.
// The tooltip theme is already configured in buildMaterialTheme().

import 'package:flutter/material.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 400),
      child: child,
    );
  }
}
