import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/jardem_colors.dart';
import 'service_badge.dart';

/// Circular service-coloured pin with a white ring and a small pointer.
class UnitPin extends StatelessWidget {
  const UnitPin({super.key, required this.service, this.size = 34, this.dimmed = false, this.symbol = false});

  final ServiceType service;
  final double size;

  /// Busy units are drawn semi-transparent.
  final bool dimmed;

  /// Show the service symbol instead of the vehicle glyph.
  final bool symbol;

  @override
  Widget build(BuildContext context) {
    final color = JardemColors.service(service);
    final pin = SizedBox(
      width: size,
      height: size * 1.18,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(width: size * 0.3, height: size * 0.3, color: Colors.white),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: size * 0.09),
              boxShadow: const [BoxShadow(color: Color(0x40102A54), blurRadius: 6, offset: Offset(0, 2))],
            ),
            alignment: Alignment.center,
            child: symbol
                ? ServiceIcon(service, size: size * 0.5)
                : Icon(ServiceIcons.vehicle(service), size: size * 0.52, color: Colors.white),
          ),
        ],
      ),
    );
    return dimmed ? Opacity(opacity: 0.55, child: pin) : pin;
  }
}

/// Large pin with a pulsing halo — the selected / assigned unit.
class HighlightedUnitPin extends StatefulWidget {
  const HighlightedUnitPin({super.key, required this.service, this.size = 46});

  final ServiceType service;
  final double size;

  /// Outer size including the halo.
  double get extent => size * 1.9;

  @override
  State<HighlightedUnitPin> createState() => _HighlightedUnitPinState();
}

class _HighlightedUnitPinState extends State<HighlightedUnitPin> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion settings (and keep widget tests settle-able).
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = JardemColors.service(widget.service);
    final size = widget.size;
    return SizedBox.square(
      dimension: widget.extent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) {
              final t = _pulse.isAnimating ? _pulse.value : 0.5;
              return Container(
                width: size * (1.15 + 0.75 * t),
                height: size * (1.15 + 0.75 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.28 * (1 - t)),
                ),
              );
            },
          ),
          Container(
            width: size * 1.3,
            height: size * 1.3,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.16)),
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            alignment: Alignment.center,
            child: Icon(ServiceIcons.vehicle(widget.service), size: size * 0.56, color: color),
          ),
        ],
      ),
    );
  }
}

/// «My location»: blue dot with a white ring and a soft halo.
class MyLocationDot extends StatelessWidget {
  const MyLocationDot({super.key, this.size = 18, this.halo = 64});

  final double size;
  final double halo;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: halo,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: JardemColors.primary.withValues(alpha: 0.12),
            border: Border.all(color: JardemColors.primary.withValues(alpha: 0.18)),
          ),
        ),
        Container(
          width: halo * 0.55,
          height: halo * 0.55,
          decoration: BoxDecoration(shape: BoxShape.circle, color: JardemColors.primary.withValues(alpha: 0.14)),
        ),
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: JardemColors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x551A8CFF), blurRadius: 8)],
          ),
        ),
      ],
    ),
  );
}

/// Incident / destination pin.
class DestinationPin extends StatelessWidget {
  const DestinationPin({super.key, this.color = JardemColors.danger, this.size = 36});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.location_on_rounded,
    color: color,
    size: size,
    shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
  );
}

/// Small round traffic marker (hotspot kind or road closure).
class TrafficBadge extends StatelessWidget {
  const TrafficBadge({super.key, required this.icon, required this.color, this.size = 24});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 1.5),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: size * 0.6, color: color),
  );
}
