import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_citizen/features/calls/incident_card.dart';
import 'package:jardem_citizen/features/onboarding/onboarding_screen.dart';
import 'package:jardem_citizen/features/tracking/tracking_screen.dart';
import 'package:jardem_citizen/state/session.dart';
import 'package:jardem_core/jardem_core.dart';

import 'support.dart';

void main() {
  group('«Вызовы»', () {
    testWidgets('empty state leads back to the map', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.text('Вызовы'));
      await tester.pumpAndSettle();
      expect(find.text('Нет активных вызовов'), findsOneWidget);
      await tester.tap(find.text('Открыть карту'));
      await tester.pumpAndSettle();
      expect(find.text('Выберите службу'), findsOneWidget);
    });

    testWidgets('active calls are listed; tap opens tracking', (tester) async {
      final h = Harness()..api.incidentList = IncidentList.fromJson(fixtureMap('incidents'));
      await h.pump(tester);
      await tester.tap(find.text('Вызовы'));
      await tester.pumpAndSettle();
      expect(find.byType(IncidentCard), findsNWidgets(2));
      expect(find.text('Экипаж назначен'), findsOneWidget);
      expect(find.text('На месте'), findsOneWidget);
      expect(find.text('Прибытие через 2 мин'), findsOneWidget);
      expect(find.text('Время прибытия: 3 мин'), findsOneWidget);
      expect(find.textContaining('№ 45831'), findsOneWidget);
      expect(find.text('ул. Назарбаева, 125, Алматы'), findsOneWidget);
      expectNoErrors(tester);

      await tester.tap(find.byKey(const Key('incident-inc-45831')));
      await tester.pumpAndSettle();
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(h.api.calls, contains('incident:inc-45831'));
    });

    testWidgets('error → retry', (tester) async {
      final h = Harness()..api.failIncidents = const ApiException.network();
      await h.pump(tester);
      await tester.tap(find.text('Вызовы'));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось загрузить'), findsOneWidget);
      h.api.failIncidents = null;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Нет активных вызовов'), findsOneWidget);
    });

    testWidgets('incident.updated reloads the list', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.text('Вызовы'));
      await tester.pumpAndSettle();
      expect(find.byType(IncidentCard), findsNothing);
      h.api.incidentList = IncidentList.fromJson(fixtureMap('incidents'));
      h.events.add(const IncidentUpdated(incidentId: 'inc-45831'));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.byType(IncidentCard), findsNWidgets(2));
    });
  });

  group('«История»', () {
    testWidgets('closed calls with status, address and time to arrival', (tester) async {
      final h = Harness()..api.incidentList = IncidentList.fromJson(fixtureMap('incidents_history'));
      await h.pump(tester);
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(find.byType(IncidentCard), findsNWidgets(2));
      expect(find.text('Завершён'), findsNWidgets(2));
      expect(find.text('Время прибытия: 1 мин'), findsOneWidget); // 75 s
      expect(find.text('Время прибытия: 3 мин'), findsOneWidget); // 173 s
      expect(find.text('ул. Назарбаева, 125, Алматы'), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('empty', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(find.text('История пуста'), findsOneWidget);
    });

    testWidgets('cancelled call without arrival', (tester) async {
      final h = Harness()
        ..api.incidentList = IncidentList(
          history: [
            incidentWith('cancelled', extra: {'eta_s': null}),
          ],
        );
      await h.pump(tester);
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(find.text('Отменён'), findsOneWidget);
      expect(find.text('Экипаж не прибыл'), findsOneWidget);
    });
  });

  group('«Профиль»', () {
    Future<Harness> open(WidgetTester tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('initials, name, phone and the six menu items', (tester) async {
      await open(tester);
      expect(find.text('АС'), findsOneWidget);
      expect(find.text('Айдос Сабденов'), findsOneWidget);
      expect(find.text('+7 777 123 45 67'), findsOneWidget);
      for (final item in [
        'Мои адреса',
        'История вызовов',
        'Способы связи',
        'Экстренные контакты',
        'Уведомления',
        'О приложении',
      ]) {
        expect(find.text(item), findsOneWidget);
      }
      expectNoErrors(tester);
    });

    testWidgets('emergency contacts dial the real numbers', (tester) async {
      final h = await open(tester);
      await tester.tap(find.text('Экстренные контакты'));
      await tester.pumpAndSettle();
      for (final n in ['112', '103', '102', '101']) {
        expect(find.byKey(Key('contact-$n')), findsOneWidget);
        await tester.tap(find.byKey(Key('contact-$n')));
        await tester.pump();
      }
      expect(h.dialled, ['112', '103', '102', '101']);
      expectNoErrors(tester);
    });

    testWidgets('about lists map and photo credits', (tester) async {
      await open(tester);
      await tester.tap(find.text('О приложении'));
      await tester.pumpAndSettle();
      expect(find.textContaining('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.textContaining('звоните 112'), findsOneWidget);
      // Every bundled photo is credited with author and licence.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('© Kalpak Travel (Flickr) · CC BY 2.0'), 150, scrollable: list);
      expect(find.text('© Kalpak Travel (Flickr) · CC BY 2.0'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('© Nurken · CC BY-SA 4.0'), 150, scrollable: list);
      expect(find.text('© Nurken · CC BY-SA 4.0'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('SIL Open Font License'), 150, scrollable: list);
      expect(find.textContaining('Manrope'), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('history from the profile; unfinished sections say so', (tester) async {
      final h = await open(tester);
      await tester.tap(find.text('История вызовов'));
      await tester.pumpAndSettle();
      expect(find.text('История пуста'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();

      for (final (item, text) in [
        ('Мои адреса', 'Сохранённые адреса'),
        ('Способы связи', 'Выбор способа связи'),
        ('Уведомления', 'Push-уведомления'),
      ]) {
        await tester.tap(find.text(item));
        await tester.pumpAndSettle();
        expect(find.text('В разработке'), findsOneWidget);
        expect(find.textContaining(text), findsOneWidget);
        await tester.tap(find.byTooltip('Назад'));
        await tester.pumpAndSettle();
      }
      expect(h.api.calls, contains('incidents'));
    });

    testWidgets('logout asks, clears the session and returns to onboarding', (tester) async {
      final h = await open(tester);
      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      expect(find.text('Выйти из профиля?'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(h.prefs.getString(kSessionKey), isNotNull);

      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();
      expect(h.prefs.getString(kSessionKey), isNull);
      expect(h.api.token, isNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });
  });
}
