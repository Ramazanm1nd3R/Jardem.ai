import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/history.dart';

Incident _inc(
  int n,
  DateTime? at, {
  String description = '',
  String category = 'Потеря сознания',
  int? arrival,
  List<TimelineEntry> timeline = const [],
}) => Incident(
  id: 'inc-$n',
  number: n,
  service: ServiceType.ambulance,
  categoryTitle: category,
  serviceTitle: 'Скорая помощь',
  description: description,
  createdAt: at,
  firstArrivalS: arrival,
  timeline: timeline,
  status: IncidentStatus.resolved,
);

void main() {
  final now = DateTime(2025, 4, 15, 12, 24);

  test('filter labels', () {
    expect(HistoryFilter.all.label, 'Все');
    expect(HistoryFilter.today.label, 'Сегодня');
  });

  group('dayLabel', () {
    test('today / yesterday / earlier', () {
      expect(dayLabel(DateTime(2025, 4, 15, 0, 1), now), 'Сегодня, 15 апреля');
      expect(dayLabel(DateTime(2025, 4, 15, 23, 59), now), 'Сегодня, 15 апреля');
      expect(dayLabel(DateTime(2025, 4, 14, 23, 59), now), 'Вчера, 14 апреля');
      expect(dayLabel(DateTime(2025, 4, 13), now), '13 апреля');
      expect(dayLabel(DateTime(2025, 4, 16), now), '16 апреля');
      expect(dayLabel(DateTime(2024, 12, 31), now), '31 декабря 2024');
    });

    test('yesterday across a month and a year', () {
      expect(dayLabel(DateTime(2025, 3, 31), DateTime(2025, 4, 1, 8)), 'Вчера, 31 марта');
      expect(dayLabel(DateTime(2024, 12, 31), DateTime(2025, 1, 1, 8)), 'Вчера, 31 декабря');
    });

    test('all months in the genitive', () {
      const months = [
        'января',
        'февраля',
        'марта',
        'апреля',
        'мая',
        'июня',
        'июля',
        'августа',
        'сентября',
        'октября',
        'ноября',
        'декабря',
      ];
      for (var m = 1; m <= 12; m++) {
        expect(dayLabel(DateTime(2023, m, 5), now), '5 ${months[m - 1]} 2023');
      }
    });
  });

  group('groupByDay', () {
    final list = [
      _inc(45814, DateTime(2025, 4, 14, 19, 5)),
      _inc(45820, DateTime(2025, 4, 15, 10, 42)),
      _inc(45815, DateTime(2025, 4, 14, 22, 36)),
      _inc(45819, DateTime(2025, 4, 15, 8, 17)),
      _inc(45700, DateTime(2025, 4, 2, 9)),
      _inc(1, null),
    ];

    test('newest day first, newest call first, undated calls skipped', () {
      final days = groupByDay(list, now);
      expect(days.map((d) => d.label), ['Сегодня, 15 апреля', 'Вчера, 14 апреля', '2 апреля']);
      expect(days[0].incidents.map((i) => i.number), [45820, 45819]);
      expect(days[1].incidents.map((i) => i.number), [45815, 45814]);
      expect(days[2].incidents.map((i) => i.number), [45700]);
      expect(days[0].day, DateTime(2025, 4, 15));
      expect(days[1].day, DateTime(2025, 4, 14));
    });

    test('today filter', () {
      final days = groupByDay(list, now, filter: HistoryFilter.today);
      expect(days, hasLength(1));
      expect(days.single.label, 'Сегодня, 15 апреля');
      expect(days.single.incidents.map((i) => i.number), [45820, 45819]);
    });

    test('today filter with nothing today', () {
      expect(groupByDay(list, DateTime(2025, 4, 20), filter: HistoryFilter.today), isEmpty);
      expect(groupByDay(const [], now), isEmpty);
      expect(groupByDay([_inc(1, null)], now), isEmpty);
    });

    test('does not mutate the input', () {
      final copy = [...list];
      groupByDay(list, now);
      expect(list.map((i) => i.id), copy.map((i) => i.id));
    });

    test('groups by local day, not by UTC day', () {
      // The same local evening and the following local morning.
      final evening = DateTime(2025, 4, 14, 23, 50).toUtc();
      final morning = DateTime(2025, 4, 15, 0, 10).toUtc();
      final days = groupByDay([_inc(1, evening), _inc(2, morning)], now);
      expect(days, hasLength(2));
      expect(days.first.incidents.single.number, 2);
    });
  });

  test('row title', () {
    expect(historyTitle(_inc(1, now, description: '  Мужчина упал  ')), 'Мужчина упал');
    expect(historyTitle(_inc(1, now, description: ' ')), 'Потеря сознания');
    expect(historyTitle(_inc(1, now, category: '')), 'Скорая помощь');
  });

  test('time to arrival', () {
    expect(historyArrival(_inc(1, now, arrival: 1920)), '32 мин');
    expect(historyArrival(_inc(1, now)), '—');
    final t = [TimelineEntry(status: 'on_scene', at: now.add(const Duration(minutes: 7)))];
    expect(historyArrival(_inc(1, now, timeline: t)), '7 мин');
    expect(historyArrival(_inc(1, now, arrival: 60, timeline: t)), '1 мин');
  });
}
