import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/features/login/login_screen.dart';
import 'package:jardem_responder/features/profile/about_screen.dart';
import 'package:jardem_responder/state/closures.dart';
import 'package:jardem_responder/state/gps.dart';
import 'package:jardem_responder/state/session.dart';
import 'package:latlong2/latlong.dart';

import 'support.dart';

Incident _past(
  int number,
  DateTime local, {
  String description = '',
  String address = 'ул. Абая, 50',
  int? arrival,
  String status = 'resolved',
}) => Incident.fromJson(
  (fixture('history') as List).first as Map<String, dynamic>
    ..['id'] = 'inc-$number'
    ..['number'] = number
    ..['description'] = description
    ..['address'] = address
    ..['status'] = status
    ..['first_arrival_s'] = arrival
    ..['created_at'] = local.toUtc().toIso8601String(),
);

void main() {
  group('«Сообщить о перекрытии»', () {
    testWidgets('report at the current position with a reason, then lift it', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      await h.push(tester, '/closure');
      expect(find.textContaining('сразу учитывается в маршрутах всех экипажей'), findsOneWidget);
      expect(find.text('Перекрытий нет.'), findsOneWidget);
      for (final r in ['ДТП', 'Ремонт', 'Затор', 'Другое']) {
        expect(find.byKey(Key('reason-$r')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('reason-Ремонт')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('closure-submit')));
      await tester.pumpAndSettle();
      expect(h.writes, ['closure:Ремонт']);
      // Default point: where the vehicle is.
      expect(h.api.reported!.at, const LatLng(43.272104, 76.978479));
      expect(h.api.reported!.minutes, 30);
      expect(find.textContaining('Перекрытие отмечено'), findsOneWidget);

      // The list is reloaded and the new closure can be lifted here.
      expect(find.byKey(const Key('closure-cl-1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('closure-cl-1')), matching: find.text('Ремонт')), findsOneWidget);
      expect(find.textContaining('отмечено вами'), findsOneWidget);
      expect(h.prefs.getStringList(kClosuresKey), ['cl-1']);

      await tester.ensureVisible(find.byKey(const Key('lift-cl-1')));
      await tester.tap(find.byKey(const Key('lift-cl-1')));
      await tester.pumpAndSettle();
      expect(h.writes, ['closure:Ремонт', 'lift:cl-1']);
      expect(find.byKey(const Key('closure-cl-1')), findsNothing);
      expect(find.text('Перекрытий нет.'), findsOneWidget);
      expect(h.prefs.getStringList(kClosuresKey), isEmpty);
      expectNoErrors(tester);
    });

    testWidgets('tapping the map picks another point', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      await h.push(tester, '/closure');
      expect(find.textContaining('текущее положение машины'), findsOneWidget);
      tester.widget<JardemMap>(find.byKey(const Key('closure-map'))).onTap!(const LatLng(43.25, 76.95));
      await tester.pumpAndSettle();
      expect(find.text('Точка выбрана на карте.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('closure-submit')));
      await tester.pumpAndSettle();
      expect(h.api.reported!.at, const LatLng(43.25, 76.95));
      expect(h.api.reported!.reason, 'ДТП');

      // A point outside the city is refused.
      tester.widget<JardemMap>(find.byKey(const Key('closure-map'))).onTap!(const LatLng(51.17, 71.45));
      await tester.pumpAndSettle();
      expect(find.text('Точка вне Алматы.'), findsOneWidget);
    });

    testWidgets('the default point stays where the vehicle was when the screen opened', (tester) async {
      final h = Harness(phase: 'returning');
      await h.pump(tester);
      await h.push(tester, '/closure');
      // The vehicle drives on towards its base.
      h.events.add(
        const UnitsMoved([UnitPosition(id: kUnitId, service: ServiceType.ambulance, lat: 43.29, lon: 76.99)]),
      );
      await tester.pumpAndSettle();
      final map = tester.widget<JardemMap>(find.byKey(const Key('closure-map')));
      expect(map.myLocation, const LatLng(43.29, 76.99));
      expect(map.destination, const LatLng(43.272104, 76.978479));
      await tester.tap(find.byKey(const Key('closure-submit')));
      await tester.pumpAndSettle();
      expect(h.api.reported!.at, const LatLng(43.272104, 76.978479));
    });

    testWidgets("someone else's closure is listed without «Снять»", (tester) async {
      final h = Harness(phase: 'available')
        ..api.closures = [const RoadClosure(id: 'cl-77', lat: 43.24, lon: 76.94, reason: 'Затор')];
      await h.pump(tester);
      await h.push(tester, '/closure');
      expect(find.byKey(const Key('closure-cl-77')), findsOneWidget);
      expect(find.byKey(const Key('lift-cl-77')), findsNothing);
      expect(find.text('Снять'), findsNothing);
    });

    testWidgets('stale own ids are forgotten once the server no longer lists them', (tester) async {
      final h = Harness(phase: 'available')
        ..extraPrefs = {
          kClosuresKey: <String>['cl-old'],
        };
      await h.pump(tester);
      await h.push(tester, '/closure');
      expect(h.prefs.getStringList(kClosuresKey), isEmpty);
    });

    testWidgets('errors are explained', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      await h.push(tester, '/closure');
      h.api.failClosure = const ApiException(422, 'no road nearby');
      await tester.tap(find.byKey(const Key('closure-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('нет дороги'), findsOneWidget);
      h.api.failClosure = const ApiException.network();
      await tester.tap(find.byKey(const Key('closure-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет соединения'), findsOneWidget);
      expect(h.prefs.getStringList(kClosuresKey), isNull);
    });

    testWidgets('fits 360 px', (tester) async {
      final h = Harness(phase: 'available')
        ..api.closures = [const RoadClosure(id: 'cl-77', lat: 43.24, lon: 76.94, reason: 'Затор')];
      await h.pump(tester, size: const Size(360, 640));
      await h.push(tester, '/closure');
      expectNoErrors(tester);
    });
  });

  group('«История вызовов»', () {
    Future<Harness> open(WidgetTester tester, List<Incident> history) async {
      final h = Harness(phase: 'available')..api.history = history;
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('nav-2')));
      await tester.pumpAndSettle();
      return h;
    }

    final calls = [
      _past(45814, DateTime(2026, 10, 10, 19, 5), description: 'Высокая температура (ребёнок)', arrival: 2280),
      _past(45820, DateTime(2026, 10, 11, 10, 42), description: 'Падение с высоты', arrival: 1920),
      _past(45819, DateTime(2026, 10, 11, 8, 17), arrival: 4320, address: 'пр. Райымбека, 201'),
      _past(45700, DateTime(2026, 9, 30, 9, 0), status: 'cancelled'),
    ];

    testWidgets('grouped by day, newest first, with number, title, address, time and arrival', (tester) async {
      await open(tester, calls);
      expect(find.text('Сегодня, 11 октября'), findsOneWidget);
      expect(find.text('Вчера, 10 октября'), findsOneWidget);
      expect(find.text('30 сентября'), findsOneWidget);
      final today = tester.getTopLeft(find.text('Сегодня, 11 октября')).dy;
      final yesterday = tester.getTopLeft(find.text('Вчера, 10 октября')).dy;
      expect(today, lessThan(yesterday));
      expect(tester.getTopLeft(find.text('#45820')).dy, lessThan(tester.getTopLeft(find.text('#45819')).dy));

      final row = find.byKey(const Key('history-inc-45820'));
      for (final t in ['#45820', 'Падение с высоты', 'ул. Абая, 50', '10:42', '32 мин']) {
        expect(
          find.descendant(of: row, matching: find.text(t)),
          findsOneWidget,
          reason: t,
        );
      }
      // No description → the category; long waits in hours.
      final other = find.byKey(const Key('history-inc-45819'));
      expect(find.descendant(of: other, matching: find.text('Экстренная помощь')), findsOneWidget);
      expect(find.descendant(of: other, matching: find.text('1 ч 12 мин')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('history-inc-45700')), matching: find.text('Отменён')),
        findsOneWidget,
      );
      expectNoErrors(tester);
    });

    testWidgets('«Сегодня» filter', (tester) async {
      await open(tester, calls);
      await tester.tap(find.text('Сегодня'));
      await tester.pumpAndSettle();
      expect(find.text('Сегодня, 11 октября'), findsOneWidget);
      expect(find.text('Вчера, 10 октября'), findsNothing);
      expect(find.byKey(const Key('history-inc-45814')), findsNothing);
      expect(find.byKey(const Key('history-inc-45820')), findsOneWidget);
      await tester.tap(find.text('Все'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-inc-45814')), findsOneWidget);
    });

    testWidgets('empty states', (tester) async {
      await open(tester, const []);
      expect(find.text('История пуста'), findsOneWidget);
      await tester.tap(find.text('Сегодня'));
      await tester.pumpAndSettle();
      expect(find.text('Сегодня вызовов не было'), findsOneWidget);
    });

    testWidgets('the live payload renders; incident.updated reloads', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('nav-2')));
      await tester.pumpAndSettle();
      expect(find.text('#45984'), findsOneWidget);
      expect(find.text('#45982'), findsOneWidget);

      h.api.history = [_past(45990, kTestNow.subtract(const Duration(minutes: 20)))];
      h.events.add(const IncidentUpdated(incidentId: 'inc-45990'));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('#45990'), findsOneWidget);
      expect(find.text('#45984'), findsNothing);
    });

    testWidgets('error → retry', (tester) async {
      final h = Harness(phase: 'available')..api.failHistory = const ApiException.network();
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('nav-2')));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось загрузить'), findsOneWidget);
      h.api.failHistory = null;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('#45984'), findsOneWidget);
    });
  });

  group('«Профиль»', () {
    Future<Harness> open(WidgetTester tester, {String phase = 'available'}) async {
      final h = Harness(phase: phase);
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('nav-4')));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('lead, phone, unit, disclaimer and menu', (tester) async {
      await open(tester);
      expect(find.text('АИ'), findsOneWidget);
      expect(find.text('Алексей Иванов'), findsOneWidget);
      expect(find.text('+7 700 123 45 67'), findsOneWidget);
      expect(find.text('Бригада СМП №7 · Скорая помощь'), findsOneWidget);
      expect(find.text('Демо-режим: вызовы и экипажи смоделированы'), findsOneWidget);
      for (final t in [
        'Моя бригада',
        'Смена и статус',
        'Сообщить о перекрытии',
        'О приложении',
        'Передавать геопозицию',
        'Выйти',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expectNoErrors(tester);
    });

    testWidgets('about: disclaimer, map and photo credits', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('menu-3')));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.textContaining('Демо-режим: вызовы и экипажи смоделированы'), findsOneWidget);
      expect(find.textContaining('В реальной экстренной ситуации звоните 112'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap'), findsWidgets);
      expect(find.text('Панорама Алматы'), findsOneWidget);
      expect(find.textContaining('Kalpak Travel'), findsOneWidget);
    });

    testWidgets('logout asks first, then clears the session', (tester) async {
      final h = await open(tester);
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(readStoredSession(h.prefs), isNotNull);

      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(readStoredSession(h.prefs), isNull);
      expect(h.api.token, isNull);
    });

    testWidgets('GPS sharing is off by default and explains the simulation', (tester) async {
      final h = await open(tester);
      expect(tester.widget<Switch>(find.byKey(const Key('gps-switch'))).value, isFalse);
      expect(find.text('Выключено: сервер моделирует движение машины по маршруту.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      expect(h.gps.requests, 0);
      expect(h.api.locations, isEmpty);
    });

    testWidgets('GPS on: a fix inside Almaty is posted every 5 s, with its speed', (tester) async {
      final h = await open(tester);
      h.gps.fix = const GpsFix(LatLng(43.25, 76.95), speedMps: 12.5);
      await tester.tap(find.byKey(const Key('gps-switch')));
      await tester.pumpAndSettle();
      expect(h.prefs.getBool(kGpsKey), isTrue);
      expect(h.api.locations, [(at: const LatLng(43.25, 76.95), speed: 12.5)]);
      expect(find.text('Включено: координаты передаются каждые 5 секунд.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(h.api.locations, hasLength(2));

      // Switched off: nothing more is sent.
      await tester.tap(find.byKey(const Key('gps-switch')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
      expect(h.api.locations, hasLength(2));
      expect(h.prefs.getBool(kGpsKey), isFalse);
    });

    testWidgets('GPS on: a fix outside the bbox is never sent', (tester) async {
      final h = await open(tester);
      h.gps.fix = const GpsFix(LatLng(51.1694, 71.4491), speedMps: 3);
      await tester.tap(find.byKey(const Key('gps-switch')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(h.gps.requests, greaterThanOrEqualTo(2));
      expect(h.api.locations, isEmpty);
      expect(find.text('Нет координат в пределах Алматы — движение моделирует сервер.'), findsOneWidget);
    });

    testWidgets('GPS on but off shift: the device is not even asked', (tester) async {
      final h = await open(tester, phase: 'off_duty');
      h.gps.fix = const GpsFix(LatLng(43.25, 76.95));
      await tester.tap(find.byKey(const Key('gps-switch')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(h.gps.requests, 0);
      expect(h.api.locations, isEmpty);
      expect(find.text('Включено: координаты начнут передаваться после выхода на смену.'), findsOneWidget);
    });

    testWidgets('GPS preference survives a restart and nonsense speed is dropped', (tester) async {
      final h = Harness(phase: 'en_route')
        ..extraPrefs = {kGpsKey: true}
        ..gps.fix = const GpsFix(LatLng(43.25, 76.95), speedMps: -1);
      await h.pump(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(h.api.locations, [(at: const LatLng(43.25, 76.95), speed: null)]);
    });
  });
}
