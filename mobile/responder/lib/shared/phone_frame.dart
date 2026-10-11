import 'package:flutter/material.dart';
import 'package:jardem_core/jardem_core.dart';

/// On wide windows (web/desktop) keeps the app in a centred phone-width column.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child, this.maxWidth = 430});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;
    return ColoredBox(
      color: const Color(0xFFE4EEFA),
      child: Center(
        child: Container(
          width: maxWidth,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(color: JardemColors.background, boxShadow: JardemColors.cardShadow),
          child: MediaQuery(
            data: media.copyWith(size: Size(maxWidth, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}
