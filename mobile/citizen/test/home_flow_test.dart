import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_citizen/features/home/home_widgets.dart';
import 'package:jardem_citizen/features/onboarding/onboarding_screen.dart';
import 'package:jardem_citizen/features/service/service_screen.dart';
import 'package:jardem_citizen/state/session.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import 'support.dart';

void main() {
  group('onboarding', () {
    testWidgets('first run: splash → sign-in sheet validates → home', (tester) async {
      final h = Harness(signedIn: false);
      await h.pump(tester);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Jardem.ai'), findsOneWidget);
      expect(find.text('Помощь ближе,\nчем кажется'), findsOneWidget);
      expectNoErrors(tester);

      await tester.tap(find.text('Начать'));
      await tester.pumpAndSettle();
      expect(find.text('Давайте знакомиться'), findsOneWidget);

      // Empty form: both validators fire, nothing is sent.
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите номер в формате +7 XXX XXX XX XX'), findsOneWidget);
      expect(find.text('Укажите имя'), findsOneWidget);
      expect(h.api.calls.where((c) => c.startsWith('login')), isEmpty);

      await tester.enterText(find.byKey(const Key('signin-phone')), '8 777 123 45 67');
      await tester.enterText(find.byKey(const Key('signin-name')), ' Айдос ');
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      // Phone is normalised, name trimmed, session persisted, home shown.
      expect(h.api.calls, contains('login:+7 777 123 45 67:Айдос'));
      expect(h.prefs.getString(kSessionKey), contains('test-token-citizen'));
      expect(find.text('Выберите службу'), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('sign-in failure is shown and can be retried', (tester) async {
      final h = Harness(signedIn: false)..api.failLogin = const ApiException.network();
      await h.pump(tester);
      await tester.tap(find.text('Начать'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signin-phone')), '+7 777 123 45 67');
      await tester.enterText(find.byKey(const Key('signin-name')), 'Айдос');
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет соединения'), findsOneWidget);
      expect(find.text('Выберите службу'), findsNothing);

      h.api.failLogin = null;
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      expect(find.text('Выберите службу'), findsOneWidget);
    });

    testWidgets('a stored session skips onboarding', (tester) async {
      final h = Harness();
      await h.pump(tester);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Выберите службу'), findsOneWidget);
      expect(h.api.token, 'stored-token');
    });
  });

  group('home map', () {
    testWidgets('sheet shows the four services and «Другое»; nav has four tabs', (tester) async {
      final h = Harness();
      await h.pump(tester);

      expect(find.text('Выберите службу'), findsOneWidget);
      for (final label in ['Скорая', 'Полиция', 'Пожарные', 'Спасатели', 'Другое']) {
        expect(find.descendant(of: find.byType(ServiceSheet), matching: find.text(label)), findsOneWidget);
      }
      for (final label in ['Карта', 'Вызовы', 'История', 'Профиль']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Моё местоположение'), findsOneWidget);
      expect(find.text('Демо-адрес'), findsOneWidget);
      expect(find.text('ул. Назарбаева, 125, Алматы'), findsOneWidget);
      // All on-duty units of the fixture are on the map.
      expect(find.byType(UnitPin), findsNWidgets(3));
      expect(find.byType(MyLocationDot), findsOneWidget);
      expect(h.location.requests, 1);
      expectNoErrors(tester);
    });

    testWidgets('disclaimer from /meta is shown and can be dismissed', (tester) async {
      final h = Harness();
      await h.pump(tester);
      expect(find.textContaining('В реальной экстренной ситуации звоните 112'), findsOneWidget);
      await tester.tap(find.byTooltip('Скрыть'));
      await tester.pumpAndSettle();
      expect(find.textContaining('В реальной экстренной ситуации'), findsNothing);
      // The 112 button stays.
      expect(find.byType(EmergencyCallButton), findsOneWidget);
    });

    testWidgets('112 button dials; failure tells the number', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.byType(EmergencyCallButton));
      await tester.pumpAndSettle();
      expect(h.dialled, ['112']);
      expect(find.textContaining('Не удалось открыть звонок'), findsNothing);

      h.dialSucceeds = false;
      await tester.tap(find.byType(EmergencyCallButton));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось открыть звонок. Наберите 112 вручную.'), findsOneWidget);
    });

    testWidgets('traffic layer is on by default with index; layers button toggles it', (tester) async {
      final h = Harness();
      await h.pump(tester);
      expect(find.text('Пробки 2/10'), findsOneWidget);
      expect(find.text('Перекрыто'), findsOneWidget);
      expect(h.api.calls.where((c) => c == 'traffic'), hasLength(1));

      await tester.tap(find.byTooltip('Слой пробок'));
      await tester.pumpAndSettle();
      expect(find.text('Пробки 2/10'), findsNothing);
      expect(find.byType(TrafficLegend), findsNothing);

      await tester.tap(find.byTooltip('Слой пробок'));
      await tester.pumpAndSettle();
      expect(find.text('Пробки 2/10'), findsOneWidget);
    });

    testWidgets('traffic error offers a retry', (tester) async {
      final h = Harness()..api.failTraffic = const ApiException(500, 'x');
      await h.pump(tester);
      expect(find.text('Пробки: повторить'), findsOneWidget);
      h.api.failTraffic = null;
      await tester.tap(find.text('Пробки: повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Пробки 2/10'), findsOneWidget);
    });

    testWidgets('units error shows a notice with retry', (tester) async {
      final h = Harness()..api.failUnits = const ApiException.network();
      await h.pump(tester);
      expect(find.textContaining('Не удалось загрузить экипажи'), findsOneWidget);
      expect(find.byType(UnitPin), findsNothing);
      h.api.failUnits = null;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Не удалось загрузить экипажи'), findsNothing);
      expect(find.byType(UnitPin), findsNWidgets(3));
    });

    testWidgets('realtime units.moved moves a marker', (tester) async {
      final h = Harness();
      await h.pump(tester);
      final pin = find.byKey(const ValueKey('unit-ambulance-12-1'));
      expect(pin, findsOneWidget);
      final before = tester.getCenter(pin);
      h.events.add(
        const UnitsMoved([
          UnitPosition(
            id: 'ambulance-12-1',
            service: ServiceType.ambulance,
            status: UnitStatus.enRoute,
            lat: 43.25,
            lon: 76.955,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(pin), isNot(before));
    });

    testWidgets('long-press moves my location; outside the city is refused', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.longPressAt(const Offset(120, 420));
      await tester.pumpAndSettle();
      expect(find.text('Местоположение изменено'), findsOneWidget);
      expect(find.textContaining('Точка на карте:'), findsOneWidget);
      expect(find.text('Демо-адрес'), findsNothing);
    });

    testWidgets('GPS fix inside Almaty replaces the demo address', (tester) async {
      final h = Harness(gpsFix: const LatLng(43.2565, 76.9285));
      await h.pump(tester);
      expect(find.text('Геопозиция: 43.2565, 76.9285'), findsOneWidget);
      expect(find.text('Демо-адрес'), findsNothing);
    });

    testWidgets('GPS fix outside Almaty falls back to the demo address', (tester) async {
      final h = Harness(gpsFix: const LatLng(51.1694, 71.4491));
      await h.pump(tester);
      expect(find.text('Демо-адрес'), findsOneWidget);
      await tester.tap(find.byTooltip('Моё местоположение'));
      await tester.pumpAndSettle();
      expect(find.text('Вы находитесь вне Алматы — показан демо-адрес.'), findsOneWidget);
    });

    for (final width in [360.0, 430.0]) {
      testWidgets('no overflow at $width px', (tester) async {
        final h = Harness();
        await h.pump(tester, size: Size(width, 780));
        expect(find.text('Выберите службу'), findsOneWidget);
        expectNoErrors(tester);
      });
    }

    testWidgets('wide web window keeps a centred 430 px column', (tester) async {
      final h = Harness();
      await h.pump(tester, size: const Size(1280, 800));
      final sheet = tester.getRect(find.byType(ServiceSheet));
      expect(sheet.width, 430);
      expect(sheet.center.dx, 640);
      expectNoErrors(tester);
    });
  });

  group('service screen', () {
    testWidgets('home → Скорая: chips, nearest crew card, call and dial', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('service-ambulance')));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceScreen), findsOneWidget);
      expect(find.text('Скорая помощь'), findsOneWidget);
      for (final chip in ['Экстренная', 'Плановая', 'Детская скорая']) {
        expect(find.text(chip), findsOneWidget);
      }
      // The last chip is scrolled into view on demand.
      await tester.scrollUntilVisible(find.text('Реанимация'), 80, scrollable: find.byType(Scrollable).first);
      expect(find.text('Реанимация'), findsOneWidget);
      // Request is filtered by the first category and sorted around me.
      expect(h.api.lastUnits!.service, ServiceType.ambulance);
      expect(h.api.lastUnits!.category, 'emergency');
      expect(h.api.lastUnits!.near, kDemoPoint);

      // Nearest free unit is highlighted and its route requested.
      expect(find.byType(HighlightedUnitPin), findsOneWidget);
      expect(h.api.calls, contains('unit:ambulance-1-2'));
      expect(find.text('Подстанция №1'), findsOneWidget);
      expect(find.text('Скорая помощь • Экстренная'), findsOneWidget);
      expect(find.text('1,8 км • 2 мин'), findsOneWidget);
      expect(find.text('Вызвать'), findsOneWidget);
      // Bottom navigation stays visible, as in the mock-up.
      expect(find.text('Профиль'), findsOneWidget);
      expectNoErrors(tester);

      await tester.tap(find.byTooltip('Позвонить 103'));
      await tester.pumpAndSettle();
      expect(h.dialled, ['103']);

      await tester.tap(find.text('Детская скорая'));
      await tester.pumpAndSettle();
      expect(h.api.lastUnits!.category, 'pediatric');
      expect(find.text('Скорая помощь • Детская скорая'), findsOneWidget);
    });

    testWidgets('each service uses its own number and categories', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.go(tester, '/map/service/police');
      expect(find.text('Патруль'), findsOneWidget);
      expect(find.text('Участковые'), findsOneWidget);
      expect(find.byTooltip('Позвонить 102'), findsOneWidget);
      await h.go(tester, '/map/service/fire');
      expect(find.text('Пожарные части'), findsOneWidget);
      expect(find.byTooltip('Позвонить 101'), findsOneWidget);
      await h.go(tester, '/map/service/rescue');
      expect(find.byTooltip('Позвонить 112'), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('switching the service from the header dropdown', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.go(tester, '/map/service/ambulance');
      await tester.tap(find.byTooltip('Сменить службу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Пожарные').last);
      await tester.pumpAndSettle();
      expect(find.text('Пожарные части'), findsOneWidget);
      expect(h.api.lastUnits!.service, ServiceType.fire);
    });

    testWidgets('no units: honest empty state, calling still possible', (tester) async {
      final h = Harness()..api.unitList = [];
      await h.pump(tester);
      await h.go(tester, '/map/service/fire');
      expect(find.text('Нет экипажей на смене'), findsOneWidget);
      expect(find.text('Вызвать'), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('all busy: says so', (tester) async {
      final h = Harness();
      h.api.unitList = [
        for (final u in Unit.listFromJson(fixture('units'))) u.copyWith(status: UnitStatus.enRoute, free: false),
      ];
      await h.pump(tester);
      await h.go(tester, '/map/service/ambulance');
      expect(find.text('Все экипажи заняты'), findsOneWidget);
      expect(find.byType(HighlightedUnitPin), findsNothing);
    });

    testWidgets('catalog error with retry', (tester) async {
      final h = Harness()..api.failCatalog = const ApiException.network();
      await h.pump(tester);
      await h.go(tester, '/map/service/ambulance');
      expect(find.text('Не удалось загрузить'), findsOneWidget);
      h.api.failCatalog = null;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Экстренная'), findsOneWidget);
      expect(find.text('Подстанция №1'), findsOneWidget);
    });

    testWidgets('category list: cards with description; picking one selects the chip', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.go(tester, '/map/service/ambulance');
      await tester.tap(find.byTooltip('Категории'));
      await tester.pumpAndSettle();
      expect(find.text('Экстренная помощь'), findsOneWidget);
      expect(find.text('Критические состояния, угроза жизни'), findsOneWidget);
      expect(find.text('Тяжёлые состояния, реанимационные бригады'), findsOneWidget);
      expectNoErrors(tester);
      await tester.tap(find.byKey(const Key('category-reanimation')));
      await tester.pumpAndSettle();
      expect(h.api.lastUnits!.category, 'reanimation');
      expect(find.text('Скорая помощь • Реанимация'), findsOneWidget);
    });

    testWidgets('nearest crews list with status chips', (tester) async {
      final h = Harness();
      h.api.unitList = [
        ...Unit.listFromJson(fixture('units')).take(2),
        Unit.listFromJson(fixture('units')).last.copyWith(status: UnitStatus.onScene, free: false),
      ];
      await h.pump(tester);
      await h.go(tester, '/map/service/ambulance');
      await tester.tap(find.text('Подстанция №1'));
      await tester.pumpAndSettle();
      expect(find.text('Ближайшие экипажи'), findsOneWidget);
      expect(find.text('Свободен'), findsNWidgets(2));
      expect(find.text('Занят'), findsOneWidget);
      expect(find.text('1,4 км • 3 мин'), findsNWidgets(2));
      expectNoErrors(tester);
    });

    testWidgets('unknown service id shows not-found', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.go(tester, '/map/service/army');
      expect(find.text('Страница не найдена'), findsOneWidget);
      await tester.tap(find.text('На главную'));
      await tester.pumpAndSettle();
      expect(find.text('Выберите службу'), findsOneWidget);
    });
  });
}
