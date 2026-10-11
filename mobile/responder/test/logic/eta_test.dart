import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_responder/logic/eta.dart';

void main() {
  final now = DateTime(2025, 4, 15, 12, 24);

  test('arrival time', () {
    expect(arrivalTime(now, 240), DateTime(2025, 4, 15, 12, 28));
    expect(arrivalTime(now, 0), now);
    expect(arrivalTime(now, null), isNull);
    expect(arrivalTime(now, -1), isNull);
    expect(arrivalTime(DateTime(2025, 4, 15, 23, 59), 120), DateTime(2025, 4, 16, 0, 1));
  });

  test('headline', () {
    expect(etaHeadline(240), '4 мин');
    expect(etaHeadline(30), '< 1 мин');
    expect(etaHeadline(1), '< 1 мин');
    expect(etaHeadline(0), 'На месте');
    expect(etaHeadline(-5), 'На месте');
    expect(etaHeadline(null), '—');
    expect(etaHeadline(4320), '1 ч 12 мин');
  });

  test('arrival line', () {
    expect(arrivalLine(now, etaS: 240, distanceM: 1200), '1,2 км · Прибытие в 12:28');
    expect(arrivalLine(now, etaS: 240), 'Прибытие в 12:28');
    expect(arrivalLine(now, distanceM: 800), '800 м');
    expect(arrivalLine(now, distanceM: 0, etaS: 0), '10 м · Прибытие в 12:24');
    expect(arrivalLine(now), 'Маршрут уточняется');
    expect(arrivalLine(now, distanceM: -1, etaS: -1), 'Маршрут уточняется');
  });

  test('week date', () {
    expect(formatWeekDate(DateTime(2025, 4, 15)), 'Вт, 15 апр. 2025');
    expect(formatWeekDate(DateTime(2026, 10, 11)), 'Вс, 11 окт. 2026');
    expect(formatWeekDate(DateTime(2026, 10, 12)), 'Пн, 12 окт. 2026');
    expect(formatWeekDate(DateTime(2025, 1, 1)), 'Ср, 1 янв. 2025');
    expect(formatWeekDate(DateTime(2025, 12, 31)), 'Ср, 31 дек. 2025');
    const months = ['янв.', 'февр.', 'марта', 'апр.', 'мая', 'июня', 'июля', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'];
    for (var m = 1; m <= 12; m++) {
      expect(formatWeekDate(DateTime(2025, m, 10)), contains(' 10 ${months[m - 1]} 2025'));
    }
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    for (var d = 0; d < 7; d++) {
      // 6 January 2025 is a Monday.
      expect(formatWeekDate(DateTime(2025, 1, 6 + d)), startsWith('${days[d]}, '));
    }
    // UTC input is shown in local time.
    final utc = DateTime.utc(2025, 4, 15, 12);
    final local = utc.toLocal();
    expect(formatWeekDate(utc), formatWeekDate(DateTime(local.year, local.month, local.day)));
  });
}
