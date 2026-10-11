import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme/jardem_colors.dart';
import '../theme/jardem_theme.dart';

/// Russian message for any error thrown by the data layer.
String errorMessage(Object error) =>
    error is ApiException ? error.userMessage : 'Что-то пошло не так. Попробуйте ещё раз.';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        if (label != null) ...[
          const SizedBox(height: 12),
          Text(label!, style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted)),
        ],
      ],
    ),
  );
}

/// Icon + title + text, optionally with an action — used for empty and error states.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.actionLabel,
    this.onAction,
    this.iconColor = JardemColors.faint,
    this.compact = false,
  });

  /// Error state with a «Повторить» button.
  factory MessageView.error(Object error, {Key? key, VoidCallback? onRetry, bool compact = false}) => MessageView(
    key: key,
    icon: Icons.cloud_off_rounded,
    title: 'Не удалось загрузить',
    text: errorMessage(error),
    actionLabel: onRetry == null ? null : 'Повторить',
    onAction: onRetry,
    compact: compact,
  );

  final IconData icon;
  final String title;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(compact ? 12 : 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 28 : 44, color: iconColor),
          SizedBox(height: compact ? 6 : 12),
          Text(title, textAlign: TextAlign.center, style: JardemTheme.text(compact ? 14 : 16, FontWeight.w800)),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(
              text!,
              textAlign: TextAlign.center,
              style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted, height: 1.35),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 4 : 10),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
