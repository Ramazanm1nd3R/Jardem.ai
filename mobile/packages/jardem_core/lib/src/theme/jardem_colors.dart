import 'package:flutter/material.dart';

import '../models/enums.dart';

/// Palette taken from the Jardem.ai mock-ups.
abstract final class JardemColors {
  static const background = Color(0xFFF3F8FE);
  static const surface = Colors.white;
  static const navy = Color(0xFF0F1E3D);
  static const muted = Color(0xFF6B7A99);
  static const faint = Color(0xFF9AA8C2);
  static const border = Color(0xFFE4ECF7);
  static const primary = Color(0xFF1A8CFF);
  static const primaryDark = Color(0xFF0B74E5);
  static const primarySoft = Color(0xFFE6F2FF);

  static const ambulance = Color(0xFFF03E3E);
  static const police = Color(0xFF1E6FE0);
  static const fire = Color(0xFFF5821F);
  static const rescue = Color(0xFF12B886);

  static const success = Color(0xFF12B886);
  static const successSoft = Color(0xFFE3F8F0);
  static const warning = Color(0xFFF5821F);
  static const warningSoft = Color(0xFFFFF0E0);
  static const danger = Color(0xFFF03E3E);
  static const dangerSoft = Color(0xFFFFECEC);

  static Color service(ServiceType s) => switch (s) {
    ServiceType.ambulance => ambulance,
    ServiceType.police => police,
    ServiceType.fire => fire,
    ServiceType.rescue => rescue,
  };

  /// Pale tint of a service colour for chips and selected cards.
  static Color serviceSoft(ServiceType s) => Color.lerp(service(s), Colors.white, 0.88)!;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x141A4B8C), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A1A4B8C), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
