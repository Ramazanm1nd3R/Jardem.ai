import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/details.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('triageFacts', () {
    test('no triage → nothing', () {
      expect(triageFacts(null), isEmpty);
    });

    test('life threat with age and missing info', () {
      final facts = triageFacts(const TriageResult(lifeThreat: true, age: 60, missing: ['address', 'victims_count']));
      expect(facts.map((f) => f.label), ['Угроза жизни', 'Возраст', 'Нужно уточнить']);
      expect(facts[0].value, 'Есть');
      expect(facts[0].alert, isTrue);
      expect(facts[1].value, '60 лет');
      expect(facts[1].alert, isFalse);
      expect(facts[2].value, 'адрес, сколько пострадавших');
      expect(facts[2].alert, isFalse);
    });

    test('calm call: only the life-threat row', () {
      final facts = triageFacts(const TriageResult());
      expect(facts, hasLength(1));
      expect(facts.single.label, 'Угроза жизни');
      expect(facts.single.value, 'Не указана');
      expect(facts.single.alert, isFalse);
    });

    test('victims and people inside', () {
      final facts = triageFacts(const TriageResult(victims: 3, peopleInside: true, age: 1));
      expect(facts.map((f) => '${f.label}=${f.value}'), [
        'Угроза жизни=Не указана',
        'Возраст=1 год',
        'Пострадавших=3',
        'Люди внутри=Да',
      ]);
      expect(facts.last.alert, isTrue);
      expect(facts[2].alert, isFalse);
    });

    test('age plural forms', () {
      String age(int a) => triageFacts(TriageResult(age: a))[1].value;
      expect(age(2), '2 года');
      expect(age(5), '5 лет');
      expect(age(21), '21 год');
    });
  });

  test('priority helpers', () {
    expect(isCritical(1), isTrue);
    expect(isCritical(0), isTrue);
    expect(isCritical(2), isFalse);
    expect(isUrgent(2), isTrue);
    expect(isUrgent(1), isFalse);
    expect(isUrgent(3), isFalse);
    expect(priorityCallLabel(1), 'Экстренный вызов');
    expect(priorityCallLabel(2), 'Срочный вызов');
    expect(priorityCallLabel(3), 'Обычный вызов');
  });

  test('address or the point', () {
    const base = Incident(id: 'i', service: ServiceType.fire, lat: 43.27251, lon: 76.979);
    expect(addressOrPoint(base), 'Точка на карте: 43.2725, 76.9790');
    expect(
      addressOrPoint(const Incident(id: 'i', service: ServiceType.fire, address: '  ул. Абая, 50 ')),
      'ул. Абая, 50',
    );
    expect(
      addressOrPoint(const Incident(id: 'i', service: ServiceType.fire, address: '  ', lat: 1, lon: 2)),
      'Точка на карте: 1.0000, 2.0000',
    );
  });

  group('equipmentSummary', () {
    test('all fine', () {
      final s = equipmentSummary(const [EquipmentItem(name: 'a'), EquipmentItem(name: 'b')]);
      expect(s.title, 'Оборудование (2/2)');
      expect(s.status, 'Все в порядке');
      expect(s.ok, isTrue);
    });

    test('something needs a check', () {
      final s = equipmentSummary(const [
        EquipmentItem(name: 'a'),
        EquipmentItem(name: 'b', ok: false),
        EquipmentItem(name: 'c', ok: false),
      ]);
      expect(s.title, 'Оборудование (1/3)');
      expect(s.status, 'Требует проверки: 2');
      expect(s.ok, isFalse);
    });

    test('empty list', () {
      final s = equipmentSummary(const []);
      expect(s.title, 'Оборудование (0/0)');
      expect(s.ok, isTrue);
    });
  });

  test('navigator link per platform', () {
    const to = LatLng(43.2725, 76.979);
    expect(navigatorUri(to, android: true, ios: false).toString(), 'geo:43.2725,76.979?q=43.2725,76.979');
    expect(
      navigatorUri(to, android: false, ios: true).toString(),
      'https://maps.apple.com/?daddr=43.2725,76.979&dirflg=d',
    );
    expect(
      navigatorUri(to, android: false, ios: false).toString(),
      'https://www.google.com/maps/dir/?api=1&destination=43.2725,76.979&travelmode=driving',
    );
    // Android wins if both are (wrongly) set.
    expect(navigatorUri(to, android: true, ios: true).scheme, 'geo');
  });
}
