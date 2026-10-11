/// «История вызовов»: filtering and grouping by local day.
library;

import 'package:jardem_core/jardem_core.dart';

enum HistoryFilter {
  all('Все'),
  today('Сегодня');

  const HistoryFilter(this.label);
  final String label;
}

class HistoryDay {
  const HistoryDay({required this.day, required this.label, required this.incidents});

  /// Local midnight of the day.
  final DateTime day;
  final String label;
  final List<Incident> incidents;
}

const List<String> _months = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', //
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// «Сегодня, 15 апреля», «Вчера, 14 апреля», «13 апреля», «31 декабря 2024».
String dayLabel(DateTime day, DateTime now) {
  final d = _dayOf(day), today = _dayOf(now);
  final date = '${d.day} ${_months[d.month - 1]}';
  if (d == today) return 'Сегодня, $date';
  if (d == DateTime(today.year, today.month, today.day - 1)) return 'Вчера, $date';
  return d.year == today.year ? date : '$date ${d.year}';
}

/// Newest day first, newest call first inside a day. Calls without a creation
/// time are skipped; with [HistoryFilter.today] only today's calls remain.
List<HistoryDay> groupByDay(List<Incident> incidents, DateTime now, {HistoryFilter filter = HistoryFilter.all}) {
  final today = _dayOf(now);
  final dated = [
    for (final i in incidents)
      if (i.createdAt != null && (filter == HistoryFilter.all || _dayOf(i.createdAt!) == today)) i,
  ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  final days = <HistoryDay>[];
  for (final i in dated) {
    final day = _dayOf(i.createdAt!);
    if (days.isEmpty || days.last.day != day) {
      days.add(HistoryDay(day: day, label: dayLabel(day, now), incidents: [i]));
    } else {
      days.last.incidents.add(i);
    }
  }
  return days;
}

/// Row title: the caller's words when there are any, else the category.
String historyTitle(Incident i) {
  final text = i.description.trim();
  if (text.isNotEmpty) return text;
  return i.categoryTitle.isEmpty ? i.serviceTitle : i.categoryTitle;
}

/// «32 мин» from call to first arrival, or «—» (cancelled before arrival).
String historyArrival(Incident i) => formatDuration(
  timeToArrivalS(
    firstArrivalS: i.firstArrivalS,
    createdAt: i.createdAt,
    arrivedAt: i.reachedAt(IncidentStatus.onScene),
  ),
);
