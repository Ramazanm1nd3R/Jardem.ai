import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/features/call/call_screen.dart';
import 'package:jardem_responder/features/chat/chat_screen.dart';
import 'package:jardem_responder/features/closure/closure_screen.dart';
import 'package:jardem_responder/features/crew/crew_screen.dart';
import 'package:jardem_responder/features/history/history_screen.dart';
import 'package:jardem_responder/features/navigation/navigation_screen.dart';
import 'package:jardem_responder/features/profile/profile_screen.dart';
import 'package:jardem_responder/features/shift/shift_screen.dart';

import 'support.dart';

void main() {
  testWidgets('header, info strip, counters, crew, vehicle and quick actions', (tester) async {
    final h = Harness();
    await h.pump(tester);
    expect(find.text('Алексей Иванов'), findsOneWidget);
    expect(find.text('Бригада СМП №7'), findsOneWidget);
    expect(find.text('Не на смене'), findsWidgets);
    expect(find.text('14:45'), findsOneWidget);
    expect(find.text('Вс, 11 окт. 2026'), findsOneWidget);
    expect(find.text('Алматы'), findsOneWidget);

    // Counters from /responder/me.
    expect(find.descendant(of: find.byKey(const Key('counter-active')), matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('counter-en-route')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('counter-on-scene')), matching: find.text('2')), findsOneWidget);
    expect(find.text('Активных\nвызовов'), findsOneWidget);

    // Crew with roles.
    expect(find.text('Моя бригада'), findsOneWidget);
    for (final t in ['Алексей', 'Мария', 'Сергей', 'Водитель', 'Фельдшер', 'Врач']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }

    // Vehicle.
    final vehicle = find.byKey(const Key('vehicle-card'));
    for (final t in ['СМП №7', 'Mercedes Sprinter', '402 AR 02', '92%', 'Не на смене']) {
      expect(
        find.descendant(of: vehicle, matching: find.text(t)),
        findsOneWidget,
        reason: t,
      );
    }

    expect(find.text('Быстрые действия'), findsOneWidget);
    for (final t in ['Текущий\nвызов', 'Карта\nвызовов', 'Сообщить о\nперекрытии', 'Связь с\nдиспетчером']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    for (final t in ['Главная', 'Карта', 'Вызовы', 'Сообщения', 'Профиль']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expectNoErrors(tester);
  });

  for (final width in const [360.0, 430.0]) {
    testWidgets('home fits $width px, on and off shift, with an incoming call', (tester) async {
      final h = Harness();
      await h.pump(tester, size: Size(width, 760));
      expectNoErrors(tester);
      await tester.tap(find.byKey(const Key('home-go-on-duty')));
      await tester.pumpAndSettle();
      expectNoErrors(tester);
      h.api.assign();
      await h.notify(tester);
      expect(find.byKey(const Key('incoming-call')), findsOneWidget);
      expectNoErrors(tester);
    });
  }

  testWidgets('going on shift from the home card', (tester) async {
    final h = Harness();
    await h.pump(tester);
    expect(find.text('Вы не на смене'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-go-on-duty')));
    await tester.pumpAndSettle();
    expect(h.writes, ['shift:true']);
    expect(find.text('Вы не на смене'), findsNothing);
    expect(find.text('На смене'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('vehicle-card')), matching: find.text('Готова')), findsOneWidget);
  });

  testWidgets('bell shows unread dispatcher messages and opens the chat', (tester) async {
    final h = Harness();
    await h.pump(tester);
    // Two dispatcher messages in the fixture, none read yet.
    expect(find.descendant(of: find.byKey(const Key('bell-badge')), matching: find.text('2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bell')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bell-badge')), findsNothing);
  });

  testWidgets('quick actions and tabs lead to their screens', (tester) async {
    final h = Harness(phase: 'available');
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('action-call')));
    await tester.pumpAndSettle();
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('Нет активного вызова'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('action-closure')));
    await tester.pumpAndSettle();
    expect(find.byType(ClosureScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-crew')));
    await tester.pumpAndSettle();
    expect(find.byType(CrewScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('duty-chip')));
    await tester.pumpAndSettle();
    expect(find.byType(ShiftScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('action-map')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationScreen), findsOneWidget);
    expect(find.byKey(const Key('nav-idle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-2')));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-4')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expectNoErrors(tester);
  });

  testWidgets('load error → retry', (tester) async {
    final h = Harness()..api.failMe = const ApiException.network();
    await h.pump(tester);
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    h.api.failMe = null;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Бригада СМП №7'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the data and says it may be stale', (tester) async {
    final h = Harness(phase: 'available');
    await h.pump(tester);
    h.api.failMe = const ApiException.network();
    await h.notify(tester, const UnitUpdated(unitId: kUnitId));
    expect(find.text('Бригада СМП №7'), findsOneWidget);
    expect(find.textContaining('Нет связи с сервером'), findsOneWidget);
  });

  testWidgets('a non-ambulance unit is an «Экипаж»', (tester) async {
    final h = Harness(service: ServiceType.fire);
    await h.pump(tester);
    expect(find.text('Экипаж ПЧ №9'), findsOneWidget);
    expect(find.text('Мой экипаж'), findsOneWidget);
    expect(find.text('Моя бригада'), findsNothing);
    await h.push(tester, '/crew');
    expect(find.text('Состав экипажа'), findsOneWidget);
    expect(find.text('Члены бригады'), findsNothing);
    expect(find.textContaining('Состав экипажа формирует диспетчерская'), findsOneWidget);
    await h.go(tester, '/profile');
    expect(find.text('Мой экипаж'), findsOneWidget);
    expect(find.text('Моя бригада'), findsNothing);
    expectNoErrors(tester);
  });

  testWidgets('crew screen: members, vehicle, equipment', (tester) async {
    final h = Harness(phase: 'available');
    await h.pump(tester);
    await h.push(tester, '/crew');
    expect(find.text('Члены бригады'), findsOneWidget);
    expect(find.text('Мария Петрова'), findsOneWidget);
    expect(find.text('Водитель · Старший бригады'), findsOneWidget);
    expect(find.text('Онлайн'), findsNWidgets(3));
    expect(find.textContaining('Добавить'), findsNothing);

    await tester.tap(find.text('Транспорт'));
    await tester.pumpAndSettle();
    expect(find.text('402 AR 02'), findsWidgets);
    expect(find.text('Подстанция №7'), findsWidgets);

    await tester.tap(find.text('Оборудование'));
    await tester.pumpAndSettle();
    expect(find.text('Оборудование (6/6)'), findsOneWidget);
    expect(find.text('Все в порядке'), findsOneWidget);
    expect(find.text('Дефибриллятор'), findsOneWidget);
    expect(find.text('ZOLL AED Plus'), findsOneWidget);
    expectNoErrors(tester);
  });

  testWidgets('crew screen opens on the requested tab', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('vehicle-card')));
    await tester.pumpAndSettle();
    expect(find.byType(CrewScreen), findsOneWidget);
    expect(find.text('Гос. номер'), findsOneWidget);
  });
}
