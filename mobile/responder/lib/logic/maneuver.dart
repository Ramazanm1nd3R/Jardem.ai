/// Turn-by-turn banner logic.
library;

import 'package:jardem_core/jardem_core.dart';

enum ManeuverArrow { straight, left, right, slightLeft, slightRight, uturn, arrive }

/// The instruction to show: the first maneuver that is not `depart`.
/// Null when the list has nothing to announce.
Maneuver? nextManeuver(List<Maneuver> maneuvers) {
  for (final m in maneuvers) {
    if (m.kind != 'depart') return m;
  }
  return null;
}

/// Arrow glyph for a maneuver kind; unknown kinds go straight.
ManeuverArrow arrowFor(String kind) => switch (kind) {
  'left' => ManeuverArrow.left,
  'right' => ManeuverArrow.right,
  'slight_left' => ManeuverArrow.slightLeft,
  'slight_right' => ManeuverArrow.slightRight,
  'uturn' => ManeuverArrow.uturn,
  'arrive' => ManeuverArrow.arrive,
  _ => ManeuverArrow.straight,
};

/// Distance to the maneuver: from the unit (`in_m`) or from the route start.
String maneuverDistance(Maneuver m) => formatDistance(m.inM ?? m.atM);

/// Closer than this the `arrive` instruction reads «Вы на месте».
const int kArrivedWithinM = 30;

/// «Поверните направо»; falls back to a generic phrase when the API sent none.
String maneuverText(Maneuver m) {
  final arrow = arrowFor(m.kind);
  if (arrow == ManeuverArrow.arrive) {
    // The API words the last instruction «Вы на месте» even 500 m before it.
    final left = m.inM ?? m.atM;
    return left != null && left > kArrivedWithinM ? 'До места вызова' : 'Вы на месте';
  }
  final text = m.text.trim();
  if (text.isNotEmpty) return text;
  return switch (arrow) {
    ManeuverArrow.left => 'Поверните налево',
    ManeuverArrow.right => 'Поверните направо',
    ManeuverArrow.slightLeft => 'Держитесь левее',
    ManeuverArrow.slightRight => 'Держитесь правее',
    ManeuverArrow.uturn => 'Развернитесь',
    ManeuverArrow.arrive => 'Вы на месте',
    ManeuverArrow.straight => 'Продолжайте движение',
  };
}

/// «улица Сатпаева» → «ул. Сатпаева», «проспект Абая» → «пр. Абая».
String shortStreet(String street) {
  final s = street.trim();
  const short = {'улица': 'ул.', 'проспект': 'пр.', 'микрорайон': 'мкр.', 'переулок': 'пер.'};
  for (final e in short.entries) {
    final word = RegExp('(^|\\s)${e.key}(\\s|\$)', caseSensitive: false);
    if (!word.hasMatch(s)) continue;
    final rest = s.replaceFirst(word, ' ').trim();
    return rest.isEmpty ? e.value : '${e.value} $rest';
  }
  return s;
}
