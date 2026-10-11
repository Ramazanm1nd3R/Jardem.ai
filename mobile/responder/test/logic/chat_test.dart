import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/chat.dart';

Message _m(String id, String sender, DateTime? at) => Message(id: id, sender: sender, at: at);

void main() {
  group('quickReplies', () {
    const a = ServiceType.ambulance;

    test('always contains the three standard answers', () {
      for (final status in UnitStatus.values) {
        for (final service in ServiceType.values) {
          final r = quickReplies(status, service);
          expect(r, containsAll(['Принял', 'В пути', 'На месте']), reason: '${status.id}/${service.id}');
          expect(r, hasLength(4));
          expect(r.toSet(), hasLength(4));
        }
      }
    });

    test('the answer matching the status comes first', () {
      expect(quickReplies(UnitStatus.assigned, a), ['Принял', 'В пути', 'На месте', 'Свободен']);
      expect(quickReplies(UnitStatus.available, a), ['Принял', 'В пути', 'На месте', 'Свободен']);
      expect(quickReplies(UnitStatus.offDuty, a).first, 'Принял');
      expect(quickReplies(UnitStatus.enRoute, a), ['В пути', 'Принял', 'На месте', 'Задерживаюсь']);
      expect(quickReplies(UnitStatus.onScene, a), ['На месте', 'Принял', 'В пути', 'Нужна помощь']);
    });

    test('transport wording is ambulance-only', () {
      expect(quickReplies(UnitStatus.transporting, a), ['Принял', 'В пути', 'На месте', 'Везём в стационар']);
      expect(quickReplies(UnitStatus.transporting, ServiceType.fire).last, 'Освобожусь через 10 мин');
      expect(quickReplies(UnitStatus.transporting, ServiceType.police).last, 'Освобожусь через 10 мин');
    });
  });

  test('outgoing text is trimmed; blank is nothing', () {
    expect(outgoingText('  Принял  '), 'Принял');
    expect(outgoingText('a'), 'a');
    expect(outgoingText(''), isNull);
    expect(outgoingText('  \n '), isNull);
  });

  group('unreadCount', () {
    final t0 = DateTime.utc(2025, 4, 15, 12);
    final list = [
      _m('1', 'dispatcher', t0),
      _m('2', 'unit', t0.add(const Duration(minutes: 1))),
      _m('3', 'dispatcher', t0.add(const Duration(minutes: 2))),
      _m('4', 'dispatcher', null),
    ];

    test('never read: all dispatcher messages', () {
      expect(unreadCount(list, null), 3);
      expect(unreadCount(const [], null), 0);
    });

    test('only dispatcher messages after the mark', () {
      expect(unreadCount(list, t0), 1);
      expect(unreadCount(list, t0.subtract(const Duration(seconds: 1))), 2);
      expect(unreadCount(list, t0.add(const Duration(minutes: 2))), 0);
      expect(unreadCount(list, t0.add(const Duration(minutes: 1, seconds: 59))), 1);
    });

    test('own messages never count', () {
      expect(unreadCount([_m('2', 'unit', t0)], null), 0);
      expect(unreadCount([_m('2', 'unit', t0)], t0.subtract(const Duration(hours: 1))), 0);
    });
  });

  test('badge text', () {
    expect(badgeText(0), '');
    expect(badgeText(-1), '');
    expect(badgeText(1), '1');
    expect(badgeText(9), '9');
    expect(badgeText(10), '9+');
    expect(badgeText(120), '9+');
  });
}
