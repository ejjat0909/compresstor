// Toast — corner notifications. Mirrors components/toast.py.
//
// Wrap the app in [ToastHost]; children call [ToastHost.of(context).show(...)]
// or the convenience helpers.

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';

enum ToastTone { info, success, warning, danger }

class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  static ToastHostState of(BuildContext context) {
    final state = context.findAncestorStateOfType<ToastHostState>();
    assert(state != null, 'ToastHost.of() called outside a ToastHost');
    return state!;
  }

  @override
  State<ToastHost> createState() => ToastHostState();
}

class ToastHostState extends State<ToastHost> {
  final _toasts = <_Toast>[];

  void show({
    required String title,
    String? message,
    ToastTone tone = ToastTone.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final toast = _Toast(
      id: UniqueKey(),
      title: title,
      message: message,
      tone: tone,
    );
    setState(() => _toasts.add(toast));
    Timer(duration, () {
      if (!mounted) return;
      setState(() => _toasts.removeWhere((t) => t.id == toast.id));
    });
  }

  void info(String title, [String? message]) =>
      show(title: title, message: message);
  void success(String title, [String? message]) =>
      show(title: title, message: message, tone: ToastTone.success);
  void warning(String title, [String? message]) =>
      show(title: title, message: message, tone: ToastTone.warning);
  void danger(String title, [String? message]) =>
      show(title: title, message: message, tone: ToastTone.danger);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 24,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: _toasts.map((t) => _ToastCard(toast: t)).toList(),
          ),
        ),
      ],
    );
  }
}

class _Toast {
  const _Toast({
    required this.id,
    required this.title,
    required this.message,
    required this.tone,
  });
  final Key id;
  final String title;
  final String? message;
  final ToastTone tone;
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.toast});
  final _Toast toast;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final AppPalette palette = theme.palette;
    final (color, icon) = _toneAssets(palette);
    return Container(
      key: toast.id,
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: AppRadius.lgAll,
        boxShadow: softShadow(palette),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(toast.title, style: theme.typography.bodyStrong),
                if (toast.message != null) ...[
                  const SizedBox(height: 2),
                  Text(toast.message!, style: theme.typography.secondary),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _toneAssets(AppPalette p) {
    switch (toast.tone) {
      case ToastTone.info:
        return (p.info, 'info');
      case ToastTone.success:
        return (p.success, 'circle-check');
      case ToastTone.warning:
        return (p.warning, 'info');
      case ToastTone.danger:
        return (p.danger, 'x');
    }
  }
}
