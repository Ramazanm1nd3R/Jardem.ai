/// Traffic level vocabulary shared by the map layers and legends.
library;

import 'dart:ui';

enum TrafficLevel {
  free('free', 'Свободно', Color(0xFF2FB56A)),
  slow('slow', 'Плотно', Color(0xFFF2C230)),
  jam('jam', 'Затор', Color(0xFFF5821F)),
  heavy('heavy', 'Пробка', Color(0xFFE03131)),
  closed('closed', 'Перекрыто', Color(0xFF495057));

  const TrafficLevel(this.id, this.label, this.color);

  final String id;
  final String label;
  final Color color;

  /// Closed roads are drawn dashed.
  bool get dashed => this == TrafficLevel.closed;

  /// Unknown or missing levels are treated as free-flowing.
  static TrafficLevel parse(Object? raw) {
    for (final level in values) {
      if (level.id == raw) return level;
    }
    return TrafficLevel.free;
  }
}

Color trafficLevelColor(Object? level) => level is TrafficLevel ? level.color : TrafficLevel.parse(level).color;

/// Level that best describes a 0–10 city traffic index.
TrafficLevel trafficIndexLevel(num? index) {
  final i = index ?? 0;
  if (i >= 8) return TrafficLevel.heavy;
  if (i >= 6) return TrafficLevel.jam;
  if (i >= 4) return TrafficLevel.slow;
  return TrafficLevel.free;
}

/// `Пробки 4/10`; the index is clamped to 0…10.
String trafficIndexLabel(num? index) {
  final i = (index ?? 0).round().clamp(0, 10);
  return 'Пробки $i/10';
}
