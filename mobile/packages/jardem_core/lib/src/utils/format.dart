/// Russian-language formatting of distances, durations and names.
library;

const String kNoValue = '—';

/// `800 м`, `1,2 км`, `12 км`. Metres are rounded to 10 m below one kilometre.
String formatDistance(num? meters) {
  if (meters == null || meters.isNaN || meters < 0) return kNoValue;
  if (meters < 995) {
    final rounded = (meters / 10).round() * 10;
    return '${rounded < 10 ? 10 : rounded} м';
  }
  final km = meters / 1000;
  if (km >= 10) return '${km.round()} км';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
}

/// `< 1 мин`, `4 мин`, `1 ч 12 мин`, `2 ч`.
String formatDuration(num? seconds) {
  if (seconds == null || seconds.isNaN || seconds < 0) return kNoValue;
  if (seconds < 60) return '< 1 мин';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes мин';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
}

/// `1,2 км • 4 мин` — parts that are unknown are dropped.
String formatDistanceEta(num? meters, num? seconds, {String separator = ' • '}) {
  final parts = [
    if (meters != null) formatDistance(meters),
    if (seconds != null) formatDuration(seconds),
  ].where((p) => p != kNoValue).toList();
  return parts.isEmpty ? kNoValue : parts.join(separator);
}

/// Local wall-clock time `HH:mm`.
String formatClock(DateTime? time) {
  if (time == null) return kNoValue;
  final t = time.toLocal();
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// `15.04.2025, 12:24` in local time.
String formatDateTime(DateTime? time) {
  if (time == null) return kNoValue;
  final t = time.toLocal();
  return '${_two(t.day)}.${_two(t.month)}.${t.year}, ${formatClock(t)}';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Up to two upper-case initials for an avatar; `?` when the name is empty.
String initials(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.substring(0, 1).toUpperCase()).join();
}

/// Russian plural form: `plural(2, 'вызов', 'вызова', 'вызовов')`.
String plural(int n, String one, String few, String many) {
  final mod100 = n.abs() % 100;
  final mod10 = n.abs() % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
