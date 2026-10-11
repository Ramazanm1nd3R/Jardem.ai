import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/maneuver.dart';

void main() {
  group('nextManeuver', () {
    test('skips depart', () {
      const list = [
        Maneuver(kind: 'depart', text: 'Начните движение'),
        Maneuver(kind: 'right', text: 'Поверните направо', inM: 158),
        Maneuver(kind: 'arrive'),
      ];
      expect(nextManeuver(list)!.kind, 'right');
    });

    test('first item when the crew is already moving', () {
      const list = [Maneuver(kind: 'uturn'), Maneuver(kind: 'left')];
      expect(nextManeuver(list)!.kind, 'uturn');
    });

    test('nothing to announce', () {
      expect(nextManeuver(const []), isNull);
      expect(nextManeuver(const [Maneuver(kind: 'depart')]), isNull);
    });

    test('arrive is announced', () {
      expect(nextManeuver(const [Maneuver(kind: 'depart'), Maneuver(kind: 'arrive')])!.kind, 'arrive');
    });
  });

  test('arrow per kind', () {
    expect(arrowFor('left'), ManeuverArrow.left);
    expect(arrowFor('right'), ManeuverArrow.right);
    expect(arrowFor('slight_left'), ManeuverArrow.slightLeft);
    expect(arrowFor('slight_right'), ManeuverArrow.slightRight);
    expect(arrowFor('uturn'), ManeuverArrow.uturn);
    expect(arrowFor('arrive'), ManeuverArrow.arrive);
    expect(arrowFor('depart'), ManeuverArrow.straight);
    expect(arrowFor('roundabout'), ManeuverArrow.straight);
    expect(arrowFor(''), ManeuverArrow.straight);
  });

  test('distance prefers in_m, falls back to at_m', () {
    expect(maneuverDistance(const Maneuver(kind: 'left', inM: 800, atM: 1500)), '800 м');
    expect(maneuverDistance(const Maneuver(kind: 'left', atM: 1500)), '1,5 км');
    expect(maneuverDistance(const Maneuver(kind: 'left')), '—');
  });

  test('text from the API, or a phrase per kind', () {
    expect(maneuverText(const Maneuver(kind: 'right', text: '  Поверните направо ')), 'Поверните направо');
    expect(maneuverText(const Maneuver(kind: 'left')), 'Поверните налево');
    expect(maneuverText(const Maneuver(kind: 'right', text: ' ')), 'Поверните направо');
    expect(maneuverText(const Maneuver(kind: 'slight_left')), 'Держитесь левее');
    expect(maneuverText(const Maneuver(kind: 'slight_right')), 'Держитесь правее');
    expect(maneuverText(const Maneuver(kind: 'uturn')), 'Развернитесь');
    expect(maneuverText(const Maneuver(kind: 'arrive')), 'Вы на месте');
    expect(maneuverText(const Maneuver(kind: 'depart')), 'Продолжайте движение');
  });

  test('the arrive instruction says how far the call still is', () {
    expect(kArrivedWithinM, 30);
    expect(maneuverText(const Maneuver(kind: 'arrive', text: 'Вы на месте', inM: 550)), 'До места вызова');
    expect(maneuverText(const Maneuver(kind: 'arrive', text: 'Вы на месте', inM: 31)), 'До места вызова');
    expect(maneuverText(const Maneuver(kind: 'arrive', text: 'Вы на месте', inM: 30)), 'Вы на месте');
    expect(maneuverText(const Maneuver(kind: 'arrive', text: 'Финиш', inM: 0)), 'Вы на месте');
    expect(maneuverText(const Maneuver(kind: 'arrive', inM: 10, atM: 3000)), 'Вы на месте');
    expect(maneuverText(const Maneuver(kind: 'arrive', atM: 3220)), 'До места вызова');
    expect(maneuverText(const Maneuver(kind: 'arrive', atM: 5)), 'Вы на месте');
    // Other kinds keep the API text whatever the distance.
    expect(maneuverText(const Maneuver(kind: 'left', text: 'Налево', inM: 5)), 'Налево');
    expect(maneuverText(const Maneuver(kind: 'depart')), 'Продолжайте движение');
  });

  test('street abbreviations', () {
    expect(shortStreet('улица Сатпаева'), 'ул. Сатпаева');
    expect(shortStreet('Оренбургская улица'), 'ул. Оренбургская');
    expect(shortStreet('проспект Абая'), 'пр. Абая');
    expect(shortStreet('микрорайон Самал-2'), 'мкр. Самал-2');
    expect(shortStreet('переулок Тихий'), 'пер. Тихий');
    expect(shortStreet('Улица Гоголя'), 'ул. Гоголя');
    expect(shortStreet('  улица  Абая  '), 'ул. Абая');
    expect(shortStreet('улица'), 'ул.');
    expect(shortStreet('Аль-Фараби'), 'Аль-Фараби');
    expect(shortStreet(''), '');
    // Only whole words are abbreviated, and only the first one.
    expect(shortStreet('Переулицах'), 'Переулицах');
    expect(shortStreet('улица Малая улица'), 'ул. Малая улица');
    expect(shortStreet('проспект улица'), 'ул. проспект');
  });
}
