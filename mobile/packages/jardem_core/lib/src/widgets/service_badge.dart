import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/jardem_colors.dart';

/// Glyphs used for each service.
abstract final class ServiceIcons {
  /// Symbol of the service (cross / shield / flame / lifebuoy).
  static IconData symbol(ServiceType s) => switch (s) {
    ServiceType.ambulance => Icons.add_rounded,
    ServiceType.police => Icons.shield_rounded,
    ServiceType.fire => Icons.local_fire_department_rounded,
    ServiceType.rescue => Icons.support_rounded,
  };

  /// Vehicle of the service, used on map pins.
  static IconData vehicle(ServiceType s) => switch (s) {
    ServiceType.ambulance => Icons.airport_shuttle_rounded,
    ServiceType.police => Icons.directions_car_filled_rounded,
    ServiceType.fire => Icons.fire_truck_rounded,
    ServiceType.rescue => Icons.support_rounded,
  };
}

/// White service symbol; the ambulance cross is drawn bold like in the logo.
class ServiceIcon extends StatelessWidget {
  const ServiceIcon(this.service, {super.key, this.size = 20, this.color = Colors.white});

  final ServiceType service;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (service == ServiceType.ambulance) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _CrossPainter(color)),
      );
    }
    return Icon(ServiceIcons.symbol(service), size: size, color: color);
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final s = size.shortestSide;
    final arm = s * 0.30, pad = s * 0.12;
    final r = Radius.circular(s * 0.06);
    canvas.drawRRect(RRect.fromLTRBR((s - arm) / 2, pad, (s + arm) / 2, s - pad, r), paint);
    canvas.drawRRect(RRect.fromLTRBR(pad, (s - arm) / 2, s - pad, (s + arm) / 2, r), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

/// Service symbol on a coloured disc or rounded square.
class ServiceBadge extends StatelessWidget {
  const ServiceBadge(this.service, {super.key, this.size = 36, this.circle = true});

  final ServiceType service;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final color = JardemColors.service(service);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.28),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ServiceIcon(service, size: size * 0.58),
    );
  }
}
