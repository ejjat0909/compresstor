// Button — shadcn-style variants + sizes, mirroring
// app/presentation/components/button.py.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/palette.dart';
import '../theme/spacing.dart';

enum ButtonVariant { primary, secondary, outline, ghost, destructive, success }

enum ButtonSize { sm, md, lg, icon, iconSm }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.md,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final String? icon;
  final bool loading;

  bool get _iconOnly => size == ButtonSize.icon || size == ButtonSize.iconSm;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    final style = _resolveVariant(palette);
    final padding = _resolvePadding();
    final radius = _resolveRadius();

    final disabled = onPressed == null || loading;
    final foreground = disabled
        ? style.foreground.withValues(alpha: 0.55)
        : style.foreground;

    final children = <Widget>[];
    if (loading) {
      children.add(SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(foreground),
        ),
      ));
    } else if (icon != null) {
      children.add(AppIcon(icon!, size: 16, color: foreground));
    }
    if (!_iconOnly && label.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        Text(
          label,
          style: theme.typography.button.copyWith(color: foreground),
        ),
      );
    }

    return _ClickShell(
      onPressed: disabled ? null : onPressed,
      radius: radius,
      background: style.background,
      hover: style.hover,
      pressed: style.pressed,
      border: style.border,
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  EdgeInsets _resolvePadding() {
    switch (size) {
      case ButtonSize.sm:
        return AppSpacing.buttonPaddingSm;
      case ButtonSize.lg:
        return AppSpacing.buttonPaddingLg;
      case ButtonSize.icon:
        return const EdgeInsets.all(8);
      case ButtonSize.iconSm:
        return const EdgeInsets.all(5);
      case ButtonSize.md:
        return AppSpacing.buttonPadding;
    }
  }

  BorderRadius _resolveRadius() {
    switch (size) {
      case ButtonSize.sm:
      case ButtonSize.iconSm:
        return AppRadius.smAll;
      case ButtonSize.lg:
        return AppRadius.lgAll;
      default:
        return AppRadius.mdAll;
    }
  }

  _VariantStyle _resolveVariant(AppPalette p) {
    switch (variant) {
      case ButtonVariant.primary:
        return _VariantStyle(
          background: p.accent,
          hover: p.accentHover,
          pressed: p.accentActive,
          foreground: p.accentForeground,
        );
      case ButtonVariant.secondary:
        return _VariantStyle(
          background: p.card,
          hover: p.cardHover,
          pressed: p.hover,
          border: p.border,
          foreground: p.text,
        );
      case ButtonVariant.outline:
        return _VariantStyle(
          background: Colors.transparent,
          hover: p.hover,
          pressed: p.active,
          border: p.border,
          foreground: p.text,
        );
      case ButtonVariant.ghost:
        return _VariantStyle(
          background: Colors.transparent,
          hover: p.hover,
          pressed: p.active,
          foreground: p.textSecondary,
        );
      case ButtonVariant.destructive:
        return _VariantStyle(
          background: p.danger,
          hover: p.dangerHover,
          pressed: p.dangerHover,
          foreground: Colors.white,
        );
      case ButtonVariant.success:
        return _VariantStyle(
          background: p.success,
          hover: p.success,
          pressed: p.success,
          foreground: Colors.white,
        );
    }
  }
}

class _VariantStyle {
  const _VariantStyle({
    required this.background,
    required this.hover,
    required this.pressed,
    required this.foreground,
    this.border,
  });
  final Color background;
  final Color hover;
  final Color pressed;
  final Color foreground;
  final Color? border;
}

class _ClickShell extends StatefulWidget {
  const _ClickShell({
    required this.child,
    required this.onPressed,
    required this.radius,
    required this.background,
    required this.hover,
    required this.pressed,
    required this.border,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius radius;
  final Color background;
  final Color hover;
  final Color pressed;
  final Color? border;

  @override
  State<_ClickShell> createState() => _ClickShellState();
}

class _ClickShellState extends State<_ClickShell> {
  bool _hovering = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final color = disabled
        ? widget.background.withValues(alpha: 0.5)
        : _down
            ? widget.pressed
            : _hovering
                ? widget.hover
                : widget.background;

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _down = true),
        onTapCancel: disabled ? null : () => setState(() => _down = false),
        onTapUp: disabled ? null : (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: color,
            borderRadius: widget.radius,
            border: widget.border == null
                ? null
                : Border.all(color: widget.border!, width: 1),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
