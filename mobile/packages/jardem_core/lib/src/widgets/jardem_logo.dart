import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/jardem_colors.dart';
import '../theme/jardem_theme.dart';

/// The four-petal mark, optionally with the «Jardem.ai» wordmark.
class JardemLogo extends StatelessWidget {
  const JardemLogo({super.key, this.size = 120, this.wordmark = true, this.horizontal = false});

  /// Side of the mark in logical pixels.
  final double size;
  final bool wordmark;

  /// Mark and wordmark side by side (headers) instead of stacked (splash).
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(
      'assets/brand/logo.svg',
      package: 'jardem_core',
      width: size,
      height: size,
      semanticsLabel: 'Jardem.ai',
    );
    if (!wordmark) return mark;
    final name = Text(
      'Jardem.ai',
      style: JardemTheme.text(horizontal ? size * 0.5 : size * 0.36, FontWeight.w800, height: 1.05),
    );
    final tagline = Text(
      'EMERGENCY AGGREGATOR PLATFORM',
      style: JardemTheme.text(
        horizontal ? size * 0.13 : size * 0.085,
        FontWeight.w700,
        color: JardemColors.navy,
      ).copyWith(letterSpacing: 0.6),
    );
    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [name, tagline],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: size * 0.06),
        name,
        SizedBox(height: size * 0.03),
        tagline,
      ],
    );
  }
}
