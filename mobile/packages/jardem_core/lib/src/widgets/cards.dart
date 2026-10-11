import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/unit.dart';
import '../theme/jardem_colors.dart';
import '../theme/jardem_theme.dart';
import '../utils/format.dart';
import '../utils/urls.dart';
import 'service_badge.dart';

/// White rounded card with the soft blue shadow from the mock-ups.
class JardemCard extends StatelessWidget {
  const JardemCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.color = Colors.white,
    this.borderColor,
    this.radius = JardemTheme.radiusCard,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadow ? JardemColors.cardShadow : null),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Bundled vehicle photo with a service-coloured placeholder.
class UnitPhoto extends StatelessWidget {
  const UnitPhoto({super.key, required this.photo, this.service, this.width = 72, this.height = 56, this.radius = 12});

  /// Basename such as `ambulance_kz_1`.
  final String photo;
  final ServiceType? service;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final asset = photoAsset(photo);
    final placeholder = Container(
      width: width,
      height: height,
      color: JardemColors.primarySoft,
      alignment: Alignment.center,
      child: service == null
          ? const Icon(Icons.local_shipping_rounded, color: JardemColors.faint)
          : ServiceIcon(service!, color: JardemColors.service(service!), size: 24),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: asset == null
          ? placeholder
          : Image.asset(
              asset,
              package: 'jardem_core',
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// Photo + name + «Скорая помощь • Экстренная» + «1,2 км • 4 мин».
class UnitCard extends StatelessWidget {
  const UnitCard({
    super.key,
    required this.unit,
    this.subtitle,
    this.extraLine,
    this.trailing,
    this.onTap,
    this.flat = false,
    this.photoWidth = 72,
    this.photoHeight = 58,
  });

  final Unit unit;

  /// Defaults to the service title.
  final String? subtitle;

  /// Replaces the distance / ETA line (e.g. «Гос. номер: 402 AR 02»).
  final String? extraLine;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Without card chrome, for embedding in another card.
  final bool flat;
  final double photoWidth;
  final double photoHeight;

  @override
  Widget build(BuildContext context) {
    final metrics = extraLine ?? formatDistanceEta(unit.distanceM, unit.etaS);
    final content = Row(
      children: [
        UnitPhoto(photo: unit.photo, service: unit.service, width: photoWidth, height: photoHeight),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unit.name.isEmpty ? unit.callsign : unit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(15, FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle ?? unit.service.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
              ),
              if (metrics != kNoValue) ...[
                const SizedBox(height: 4),
                Text(
                  metrics,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(13, FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
    if (flat) return InkWell(onTap: onTap, child: content);
    return JardemCard(onTap: onTap, child: content);
  }
}
