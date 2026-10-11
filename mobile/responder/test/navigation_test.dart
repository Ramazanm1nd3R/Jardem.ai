import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/features/navigation/navigation_screen.dart';
import 'package:latlong2/latlong.dart';

import 'support.dart';

JardemMap _map(WidgetTester tester) => tester.widget<JardemMap>(find.byType(JardemMap));

void main() {
  testWidgets('en route: maneuver banner, traffic route, ETA sheet', (tester) async {
    final h = Harness(phase: 'en_route');
    await h.pump(tester);
    await h.go(tester, '/map');

    final banner = find.byKey(const Key('maneuver-banner'));
    expect(banner, findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('60 м')), findsOneWidget); // in_m 61
    expect(find.descendant(of: banner, matching: find.text('Поверните направо\nул. Демченко')), findsOneWidget);
    expect(find.byKey(const Key('arrow-right')), findsOneWidget);

    // 221 s, 3124 m at 14:45.
    expect(find.descendant(of: find.byKey(const Key('nav-sheet')), matching: find.text('4 мин')), findsOneWidget);
    expect(find.text('3,1 км · Прибытие в 14:48'), findsOneWidget);
    expect(find.text('Экстренный вызов'), findsOneWidget);
    expect(find.text('ул. Назарбаева, 125, Алматы'), findsOneWidget);
    expectButton('step-arrive', 'Подтвердить прибытие');

    // The line comes from /route (traffic sections), from the unit to the incident.
    expect(h.api.calls, contains('route'));
    final map = _map(tester);
    expect(map.routes.last.sections, isNotEmpty);
    expect(map.routes.first.points, map.routes.last.points); // casing under the coloured line
    expect(map.destination, const LatLng(43.2725, 76.979));
    expect(map.traffic, isNotNull);
    expect(map.units.where((u) => u.highlighted).single.id, kUnitId);
    // Peers of the same service, without a duplicate of this unit.
    expect(map.units.map((u) => u.id), ['peer-1', kUnitId]);
    expect(h.api.calls, contains('units:ambulance'));
    expectNoErrors(tester);
  });

  testWidgets('the route is re-requested every 10 s and on traffic.updated', (tester) async {
    final h = Harness(phase: 'en_route');
    await h.pump(tester);
    await h.go(tester, '/map');
    int routes() => h.api.calls.where((c) => c == 'route').length;
    expect(routes(), 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(routes(), 2);
    h.events.add(const TrafficUpdated());
    await tester.pumpAndSettle();
    expect(routes(), 3);
  });

  testWidgets('units.moved moves the unit marker without a refetch', (tester) async {
    final h = Harness(phase: 'en_route');
    await h.pump(tester);
    await h.go(tester, '/map');
    final before = h.api.calls.where((c) => c == 'me').length;
    h.events.add(
      const UnitsMoved([
        UnitPosition(
          id: kUnitId,
          service: ServiceType.ambulance,
          status: UnitStatus.enRoute,
          lat: 43.2801,
          lon: 76.9885,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final mine = _map(tester).units.singleWhere((u) => u.highlighted);
    expect(mine.position, const LatLng(43.2801, 76.9885));
    expect(h.api.calls.where((c) => c == 'me').length, before);
  });

  testWidgets('«Открыть в навигаторе» hands the destination to the platform', (tester) async {
    final h = Harness(phase: 'en_route');
    await h.pump(tester);
    await h.go(tester, '/map');
    await tester.tap(find.byKey(const Key('open-navigator')));
    await tester.pumpAndSettle();
    expect(h.navigated, [const LatLng(43.2725, 76.979)]);

    h.navigatorOpens = false;
    await tester.tap(find.byKey(const Key('open-navigator')));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось открыть навигатор на этом устройстве.'), findsOneWidget);
  });

  testWidgets('assigned: route preview, the incoming card replaces the sheet', (tester) async {
    final h = Harness(phase: 'assigned');
    await h.pump(tester);
    await h.go(tester, '/map');
    expect(find.byKey(const Key('nav-sheet')), findsNothing);
    expect(find.byKey(const Key('incoming-call')), findsOneWidget);
    expect(find.byKey(const Key('maneuver-banner')), findsNothing);
    expect(_map(tester).routes, isNotEmpty);
  });

  testWidgets('on scene: no route, no banner, the next buttons', (tester) async {
    final h = Harness(phase: 'on_scene');
    await h.pump(tester);
    await h.go(tester, '/map');
    expect(find.byKey(const Key('maneuver-banner')), findsNothing);
    expect(_map(tester).routes, isEmpty);
    expect(h.api.calls, isNot(contains('route')));
    expect(find.descendant(of: find.byKey(const Key('nav-sheet')), matching: find.text('На месте')), findsOneWidget);
    expectButton('step-transport', 'Пациент загружен');
  });

  testWidgets('no call: idle sheet; layers button hides the traffic', (tester) async {
    final h = Harness(phase: 'available');
    await h.pump(tester);
    await h.go(tester, '/map');
    expect(find.text('Нет активного вызова'), findsOneWidget);
    expect(find.textContaining('Маршрут появится'), findsOneWidget);
    expect(_map(tester).destination, isNull);
    expect(_map(tester).traffic, isNotNull);
    await tester.tap(find.byKey(const Key('map-layers')));
    await tester.pumpAndSettle();
    expect(_map(tester).traffic, isNull);
    for (final k in ['map-recenter', 'map-zoom-in', 'map-zoom-out']) {
      await tester.tap(find.byKey(Key(k)));
      await tester.pumpAndSettle();
    }
    expectNoErrors(tester);
  });

  testWidgets('off duty hint', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await h.go(tester, '/map');
    expect(find.textContaining('Вы не на смене'), findsOneWidget);
  });

  for (final width in const [360.0, 430.0]) {
    testWidgets('fits $width px while en route', (tester) async {
      final h = Harness(phase: 'en_route');
      await h.pump(tester, size: Size(width, 720));
      await h.go(tester, '/map');
      expect(find.byType(ManeuverBanner), findsOneWidget);
      expectNoErrors(tester);
    });
  }
}
