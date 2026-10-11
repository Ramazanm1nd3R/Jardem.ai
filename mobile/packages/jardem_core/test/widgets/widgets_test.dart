import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../fixtures.dart';

Widget _host(Widget child, {double width = 390, double height = 600}) => MaterialApp(
  theme: JardemTheme.light(),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, height: height, child: child),
    ),
  ),
);

void main() {
  setUpAll(() => JardemMap.tilesEnabled = false);

  testWidgets('theme uses bundled Manrope and the mock-up palette', (tester) async {
    final theme = JardemTheme.light();
    expect(theme.textTheme.bodyMedium!.fontFamily, 'packages/jardem_core/Manrope');
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F8FE));
    expect(theme.colorScheme.primary, const Color(0xFF1A8CFF));
    expect(JardemColors.service(ServiceType.ambulance), const Color(0xFFF03E3E));
    expect(JardemColors.service(ServiceType.police), const Color(0xFF1E6FE0));
    expect(JardemColors.service(ServiceType.fire), const Color(0xFFF5821F));
    expect(JardemColors.service(ServiceType.rescue), const Color(0xFF12B886));
    final style = JardemTheme.text(14, FontWeight.w700);
    expect(style.fontVariations, const [FontVariation('wght', 700)]);
    expect(style.color, const Color(0xFF0F1E3D));
  });

  testWidgets('StatusChip shows Свободен / Занят with the right tone', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            StatusChip.unit(UnitStatus.available),
            StatusChip.unit(UnitStatus.enRoute),
            StatusChip.unit(UnitStatus.offDuty),
            StatusChip.incident(IncidentStatus.resolved),
          ],
        ),
      ),
    );
    expect(find.text('Свободен'), findsOneWidget);
    expect(find.text('Занят'), findsOneWidget);
    expect(find.text('Не на смене'), findsOneWidget);
    expect(find.text('Завершён'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Свободен')).style!.color, JardemColors.success);
    expect(tester.widget<Text>(find.text('Занят')).style!.color, JardemColors.warning);
  });

  testWidgets('UnitCard shows name, subtitle, distance and ETA', (tester) async {
    final unit = Unit.fromJson(fixtureMap('unit_detail'));
    var tapped = 0;
    await tester.pumpWidget(
      _host(UnitCard(unit: unit, subtitle: 'Скорая помощь • Экстренная', onTap: () => tapped++), height: 120),
    );
    expect(find.text('Подстанция №1'), findsOneWidget);
    expect(find.text('Скорая помощь • Экстренная'), findsOneWidget);
    expect(find.text('1,8 км • 2 мин'), findsOneWidget);
    await tester.tap(find.byType(UnitCard));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UnitCard: extra line replaces metrics; defaults to the service title', (tester) async {
    final unit = Unit.fromJson(fixtureMap('unit_detail'));
    await tester.pumpWidget(
      _host(UnitCard(unit: unit, extraLine: 'Гос. номер: ${unit.plate}', flat: true), height: 120),
    );
    expect(find.text('Гос. номер: 527 TK 02'), findsOneWidget);
    expect(find.text('Скорая помощь'), findsOneWidget);
    expect(find.textContaining('км'), findsNothing);
  });

  testWidgets('UnitCard fits a 300 px wide column without overflow', (tester) async {
    final unit = Unit.fromJson({
      'id': 'u',
      'service': 'rescue',
      'name': 'Поисково-спасательная группа №12 имени очень длинного названия',
      'distance_m': 12400,
      'eta_s': 4320,
    });
    await tester.pumpWidget(
      _host(UnitCard(unit: unit, trailing: StatusChip.unit(UnitStatus.available)), width: 300, height: 120),
    );
    expect(find.text('12 км • 1 ч 12 мин'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons: tap, loading and disabled states', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            PrimaryButton(label: 'Вызвать', onPressed: () => taps++),
            PrimaryButton(label: 'Отправка', loading: true, onPressed: () => taps += 10),
            SecondaryButton(label: 'Позвонить', icon: Icons.phone, onPressed: () => taps += 100),
            SquareIconButton(icon: Icons.layers, tooltip: 'Слои', onPressed: () => taps += 1000),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Вызвать'));
    expect(taps, 1);
    expect(find.text('Отправка'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
    expect(taps, 1);
    await tester.tap(find.text('Позвонить'));
    expect(taps, 101);
    await tester.tap(find.byTooltip('Слои'));
    expect(taps, 1101);
  });

  testWidgets('MessageView.error shows the Russian message and retries', (tester) async {
    var retried = 0;
    await tester.pumpWidget(_host(MessageView.error(const ApiException.network(), onRetry: () => retried++)));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    expect(find.textContaining('Нет соединения'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    expect(retried, 1);
    expect(errorMessage(StateError('x')), 'Что-то пошло не так. Попробуйте ещё раз.');
    expect(errorMessage(const ApiException(429, 'x')), contains('Слишком много'));
  });

  testWidgets('JardemLogo renders the wordmark', (tester) async {
    await tester.pumpWidget(_host(const JardemLogo(size: 100)));
    await tester.pump();
    expect(find.text('Jardem.ai'), findsOneWidget);
    expect(find.text('EMERGENCY AGGREGATOR PLATFORM'), findsOneWidget);
    await tester.pumpWidget(_host(const JardemLogo(size: 40, wordmark: false)));
    expect(find.text('Jardem.ai'), findsNothing);
    await tester.pumpWidget(_host(const JardemLogo(size: 40, horizontal: true)));
    expect(find.text('Jardem.ai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ServiceBadge and pins build for every service', (tester) async {
    await tester.pumpWidget(
      _host(
        Wrap(
          children: [
            for (final s in ServiceType.values) ...[
              ServiceBadge(s),
              ServiceBadge(s, circle: false),
              UnitPin(service: s),
              UnitPin(service: s, dimmed: true, symbol: true),
            ],
            const MyLocationDot(),
            const DestinationPin(),
          ],
        ),
      ),
    );
    expect(find.byType(ServiceBadge), findsNWidgets(8));
    expect(find.byType(UnitPin), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });

  group('JardemMap', () {
    const a = LatLng(43.24, 76.94), b = LatLng(43.25, 76.95);

    test('fitFor needs two distinct points', () {
      expect(JardemMap.fitFor(null, EdgeInsets.zero), isNull);
      expect(JardemMap.fitFor(const [], EdgeInsets.zero), isNull);
      expect(JardemMap.fitFor(const [a], EdgeInsets.zero), isNull);
      expect(JardemMap.fitFor(const [a, a], EdgeInsets.zero), isNull);
      expect(JardemMap.fitFor(const [a, b], EdgeInsets.zero), isNotNull);
    });

    test('attribution and tile source', () {
      expect(JardemMap.attribution, contains('© OpenStreetMap contributors'));
      expect(
        MapTiles.cartoVoyager.urlTemplate,
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      );
      expect(MapTiles.cartoVoyager.subdomains, ['a', 'b', 'c', 'd']);
      expect(MapTiles.cartoVoyager.attribution, '© OpenStreetMap contributors, © CARTO');
      expect(MapTiles.fromEnvironment().urlTemplate, MapTiles.osm.urlTemplate);
    });

    testWidgets('renders all layers and reports taps', (tester) async {
      final traffic = TrafficData.fromJson(fixtureMap('traffic'));
      final route = RouteResult.fromJson(fixtureMap('route'));
      final tappedUnits = <String>[];
      LatLng? longPressed;
      await tester.pumpWidget(
        _host(
          JardemMap(
            center: kDemoPoint,
            zoom: 13,
            myLocation: kDemoPoint,
            destination: b,
            traffic: traffic,
            routes: [
              MapRoute(points: route.geometry, dashed: true, color: JardemColors.ambulance),
              MapRoute.traffic(route),
            ],
            units: const [
              MapUnit(id: 'u1', position: LatLng(43.2445, 76.9457), service: ServiceType.ambulance, highlighted: true),
              MapUnit(id: 'u2', position: LatLng(43.2545, 76.9600), service: ServiceType.police, dimmed: true),
            ],
            onUnitTap: tappedUnits.add,
            onLongPress: (p) => longPressed = p,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsNothing, reason: 'tiles are disabled in tests');
      expect(find.byType(HighlightedUnitPin), findsOneWidget);
      expect(find.byType(UnitPin), findsOneWidget);
      expect(find.byType(MyLocationDot), findsOneWidget);
      expect(find.byType(DestinationPin), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNWidgets(2));
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.text(JardemMap.attribution), findsOneWidget);

      await tester.tap(find.byType(UnitPin));
      expect(tappedUnits, ['u2']);

      await tester.longPressAt(tester.getCenter(find.byType(FlutterMap)) + const Offset(-120, 200));
      await tester.pump();
      expect(longPressed, isNotNull);
      expect(inServiceArea(longPressed), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('markers glide between positions', (tester) async {
      Widget map(LatLng at) => _host(
        JardemMap(
          center: a,
          zoom: 14,
          interactive: false,
          moveDuration: const Duration(milliseconds: 1000),
          units: [MapUnit(id: 'u1', position: at, service: ServiceType.fire)],
        ),
      );
      await tester.pumpWidget(map(a));
      await tester.pump();
      final start = tester.getCenter(find.byType(UnitPin));

      await tester.pumpWidget(map(b));
      await tester.pump();
      expect(tester.getCenter(find.byType(UnitPin)), start, reason: 'animation starts at the old position');

      await tester.pump(const Duration(milliseconds: 500));
      final mid = tester.getCenter(find.byType(UnitPin));
      await tester.pump(const Duration(milliseconds: 600));
      final end = tester.getCenter(find.byType(UnitPin));

      expect(end, isNot(start));
      expect((mid.dx - (start.dx + end.dx) / 2).abs(), lessThan(1.5));
      expect((mid.dy - (start.dy + end.dy) / 2).abs(), lessThan(1.5));
      // b is north-east of a → right and up on screen.
      expect(end.dx, greaterThan(start.dx));
      expect(end.dy, lessThan(start.dy));

      // A newly appearing unit shows up at its position without animating.
      await tester.pumpWidget(
        _host(
          JardemMap(
            center: a,
            zoom: 14,
            interactive: false,
            units: const [
              MapUnit(id: 'u1', position: b, service: ServiceType.fire),
              MapUnit(id: 'u2', position: a, service: ServiceType.rescue),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(UnitPin), findsNWidgets(2));
      expect(tester.getCenter(find.byType(UnitPin).last), start);
    });

    testWidgets('pulsing pin stops for reduced-motion users', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(const HighlightedUnitPin(service: ServiceType.ambulance)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HighlightedUnitPin), findsOneWidget);
    });
  });
}
