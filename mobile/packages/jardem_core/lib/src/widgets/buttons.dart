import 'package:flutter/material.dart';

import '../theme/jardem_colors.dart';
import '../theme/jardem_theme.dart';

/// Filled pill button («Начать», «Вызвать»). Shows a spinner while [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.color = JardemColors.primary,
    this.loading = false,
    this.height = 52,
    this.radius = 999,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final Color color;
  final bool loading;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: enabled
              ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]
              : null,
        ),
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.45),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
            textStyle: JardemTheme.text(16, FontWeight.w700, color: Colors.white),
          ),
          child: loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                    Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 20)],
                  ],
                ),
        ),
      ),
    );
  }
}

/// White outlined button («Позвонить», «Написать»).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = JardemColors.primary,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: JardemColors.navy,
        side: const BorderSide(color: JardemColors.border, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: JardemTheme.text(14, FontWeight.w700),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

/// Square white icon button (map controls, the phone button next to «Вызвать»).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
    this.color = JardemColors.navy,
    this.background = Colors.white,
    this.bordered = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color color;
  final Color background;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      elevation: bordered ? 0 : 3,
      shadowColor: const Color(0x331A4B8C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: bordered ? const BorderSide(color: JardemColors.border, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: color, size: size * 0.46),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
