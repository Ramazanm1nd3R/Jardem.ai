import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';

void main() {
  group('formatDistance', () {
    test('metres below one kilometre are rounded to 10 m', () {
      expect(formatDistance(800), '800 м');
      expect(formatDistance(804), '800 м');
      expect(formatDistance(805), '810 м');
      expect(formatDistance(14), '10 м');
      expect(formatDistance(15), '20 м');
      expect(formatDistance(994), '990 м');
    });

    test('never shows less than 10 m', () {
      expect(formatDistance(0), '10 м');
      expect(formatDistance(4), '10 м');
      expect(formatDistance(5), '10 м');
      expect(formatDistance(9), '10 м');
    });

    test('switches to kilometres at 995 m', () {
      expect(formatDistance(994.9), '990 м');
      expect(formatDistance(995), '1,0 км');
      expect(formatDistance(1000), '1,0 км');
    });

    test('kilometres use a decimal comma', () {
      expect(formatDistance(1200), '1,2 км');
      expect(formatDistance(1833), '1,8 км');
      expect(formatDistance(2449), '2,4 км');
      expect(formatDistance(9940), '9,9 км');
    });

    test('ten kilometres and more are whole numbers', () {
      expect(formatDistance(9999), '10,0 км');
      expect(formatDistance(10000), '10 км');
      expect(formatDistance(12400), '12 км');
      expect(formatDistance(12600), '13 км');
    });

    test('invalid input gives a dash', () {
      expect(formatDistance(null), '—');
      expect(formatDistance(-1), '—');
      expect(formatDistance(double.nan), '—');
      expect(kNoValue, '—');
    });
  });

  group('formatDuration', () {
    test('under a minute', () {
      expect(formatDuration(0), '< 1 мин');
      expect(formatDuration(59), '< 1 мин');
      expect(formatDuration(59.9), '< 1 мин');
    });

    test('minutes are rounded', () {
      expect(formatDuration(60), '1 мин');
      expect(formatDuration(89), '1 мин');
      expect(formatDuration(90), '2 мин');
      expect(formatDuration(240), '4 мин');
      expect(formatDuration(141), '2 мин');
      expect(formatDuration(3569), '59 мин');
    });

    test('hours and minutes', () {
      expect(formatDuration(3570), '1 ч');
      expect(formatDuration(3600), '1 ч');
      expect(formatDuration(4320), '1 ч 12 мин');
      expect(formatDuration(3660), '1 ч 1 мин');
      expect(formatDuration(7200), '2 ч');
      expect(formatDuration(7140), '1 ч 59 мин');
      expect(formatDuration(9000), '2 ч 30 мин');
    });

    test('invalid input gives a dash', () {
      expect(formatDuration(null), '—');
      expect(formatDuration(-1), '—');
      expect(formatDuration(double.nan), '—');
    });
  });

  group('formatDistanceEta', () {
    test('joins both parts with a bullet', () {
      expect(formatDistanceEta(1200, 240), '1,2 км • 4 мин');
      expect(formatDistanceEta(800, 120), '800 м • 2 мин');
    });

    test('custom separator', () {
      expect(formatDistanceEta(1200, 240, separator: ' · '), '1,2 км · 4 мин');
    });

    test('drops unknown parts', () {
      expect(formatDistanceEta(null, 240), '4 мин');
      expect(formatDistanceEta(1200, null), '1,2 км');
      expect(formatDistanceEta(null, null), '—');
      expect(formatDistanceEta(-5, 240), '4 мин');
      expect(formatDistanceEta(1200, -1), '1,2 км');
      expect(formatDistanceEta(-5, -1), '—');
    });
  });

  group('clock and date', () {
    test('formatClock pads hours and minutes', () {
      expect(formatClock(DateTime(2025, 4, 15, 9, 5)), '09:05');
      expect(formatClock(DateTime(2025, 4, 15, 12, 24)), '12:24');
      expect(formatClock(DateTime(2025, 4, 15, 0, 0)), '00:00');
      expect(formatClock(null), '—');
    });

    test('formatClock converts UTC to local time', () {
      final utc = DateTime.utc(2025, 4, 15, 7, 24);
      final local = utc.toLocal();
      expect(formatClock(utc), '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}');
    });

    test('formatDateTime', () {
      expect(formatDateTime(DateTime(2025, 4, 5, 12, 24)), '05.04.2025, 12:24');
      expect(formatDateTime(DateTime(2026, 12, 31, 23, 59)), '31.12.2026, 23:59');
      expect(formatDateTime(null), '—');
    });
  });

  group('initials', () {
    test('one or two words', () {
      expect(initials('Айдос'), 'А');
      expect(initials('Алексей Иванов'), 'АИ');
      expect(initials('алексей иванов'), 'АИ');
    });

    test('at most two letters, extra whitespace ignored', () {
      expect(initials('  Мария   Петровна  Ким '), 'МП');
    });

    test('empty names', () {
      expect(initials(null), '?');
      expect(initials(''), '?');
      expect(initials('   '), '?');
    });
  });

  group('plural', () {
    String calls(int n) => plural(n, 'вызов', 'вызова', 'вызовов');

    test('one', () {
      expect(calls(1), 'вызов');
      expect(calls(21), 'вызов');
      expect(calls(101), 'вызов');
    });

    test('few', () {
      expect(calls(2), 'вызова');
      expect(calls(3), 'вызова');
      expect(calls(4), 'вызова');
      expect(calls(22), 'вызова');
      expect(calls(24), 'вызова');
    });

    test('many', () {
      expect(calls(0), 'вызовов');
      expect(calls(5), 'вызовов');
      expect(calls(10), 'вызовов');
      expect(calls(11), 'вызовов');
      expect(calls(12), 'вызовов');
      expect(calls(14), 'вызовов');
      expect(calls(15), 'вызовов');
      expect(calls(20), 'вызовов');
      expect(calls(25), 'вызовов');
      expect(calls(111), 'вызовов');
      expect(calls(114), 'вызовов');
    });

    test('hundreds do not confuse the teens rule', () {
      expect(calls(110), 'вызовов');
      expect(calls(115), 'вызовов');
      expect(calls(121), 'вызов');
      expect(calls(122), 'вызова');
    });

    test('negative numbers use the absolute value', () {
      expect(calls(-1), 'вызов');
      expect(calls(-2), 'вызова');
      expect(calls(-11), 'вызовов');
      expect(calls(-21), 'вызов');
    });
  });
}
