// Toast — corner notifications. Mirrors components/toast.py.
//
// Wrap the app in [ToastHost]; children call [ToastHost.of(context).show(...)]
// or the convenience helpers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          top: 24,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: _toasts.map((t) => _ToastCard(toast: t)).toList(),
            ),
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

class _ToastCard extends StatefulWidget {
  const _ToastCard({required this.toast});
  final _Toast toast;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> {
  bool _copied = false;

  void _onCopy() {
    final text = widget.toast.message != null
        ? '${widget.toast.title}\n${widget.toast.message}'
        : widget.toast.title;
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final AppPalette palette = theme.palette;
    final (accent, icon) = _toneAssets(palette);
    return Container(
      key: widget.toast.id,
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 240),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: AppRadius.lgAll,
        boxShadow: softShadow(palette),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 3, color: accent),
              Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(icon, size: 18, color: accent),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.toast.title,
                            style: theme.typography.bodyStrong,
                          ),
                          if (widget.toast.message != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.toast.message!,
                              style: theme.typography.secondary,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _copied ? null : _onCopy,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _copied
                              ? AppIcon('check', size: 14, color: palette.accent, key: const ValueKey('check'))
                              : AppIcon('copy', size: 14, color: palette.accent, key: const ValueKey('copy')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  (Color, String) _toneAssets(AppPalette p) {
    switch (widget.toast.tone) {
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
