/// Arrival clock and the navigation sheet's summary lines.
library;

import 'package:jardem_core/jardem_core.dart';

/// Wall-clock arrival time: [now] plus the remaining [etaS]; null when unknown.
DateTime? arrivalTime(DateTime now, int? etaS) => etaS == null || etaS < 0 ? null : now.add(Duration(seconds: etaS));

/// Big number on the navigation sheet: «4 мин»; «На месте» at zero.
String etaHeadline(int? etaS) {
  if (etaS == null) return kNoValue;
  return etaS <= 0 ? 'На месте' : formatDuration(etaS);
}

/// «1,2 км · Прибытие в 12:28»; unknown parts are dropped.
String arrivalLine(DateTime now, {int? etaS, int? distanceM}) {
  final at = arrivalTime(now, etaS);
  final parts = [
    if (distanceM != null && distanceM >= 0) formatDistance(distanceM),
    if (at != null) 'Прибытие в ${formatClock(at)}',
  ];
  return parts.isEmpty ? 'Маршрут уточняется' : parts.join(' · ');
}

const List<String> _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const List<String> _monthsShort = [
  'янв.',
  'февр.',
  'марта',
  'апр.',
  'мая',
  'июня',
  'июля',
  'авг.',
  'сент.',
  'окт.',
  'нояб.',
  'дек.',
];

/// «Вт, 15 апр. 2025» in local time — the home screen's date.
String formatWeekDate(DateTime time) {
  final t = time.toLocal();
  return '${_weekdays[t.weekday - 1]}, ${t.day} ${_monthsShort[t.month - 1]} ${t.year}';
}
