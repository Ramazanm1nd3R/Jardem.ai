import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/features/call/call_screen.dart';
import 'package:jardem_responder/features/navigation/navigation_screen.dart';

import 'support.dart';

void main() {
  group('incoming call', () {
    testWidgets('appears on every tab with number, category, priority, ETA and the accept button', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      expect(find.byKey(const Key('incoming-call')), findsNothing);

      h.api.assign();
      await h.notify(tester);
      final card = find.byKey(const Key('incoming-call'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Новый вызов #45984')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Экстренная помощь')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('ул. Назарбаева, 125, Алматы')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Экстренный')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('4 мин')), findsOneWidget); // 234 s
      expect(find.descendant(of: card, matching: find.text('3,2 км')), findsOneWidget); // 3220 m
      expectButton('incoming-accept', 'Принять вызов');

      for (var tab = 1; tab <= 4; tab++) {
        await tester.tap(find.byKey(Key('nav-$tab')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('incoming-call')), findsOneWidget, reason: 'tab $tab');
        expectNoErrors(tester);
      }
    });

    testWidgets('the poll alone (no realtime event) also brings the call in', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      h.api.assign();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('incoming-call')), findsOneWidget);
    });

    testWidgets('the card opens the call details', (tester) async {
      final h = Harness(phase: 'assigned');
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('incoming-details')));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('Вызов #45984'), findsOneWidget);
    });
  });

  testWidgets('ambulance: accept → arrive → transport → complete across the screens', (tester) async {
    final h = Harness(phase: 'available');
    await h.pump(tester);
    h.api.assign();
    await h.notify(tester);

    // Accept from the incoming card on the home tab.
    await tester.tap(find.byKey(const Key('incoming-accept')));
    await tester.pumpAndSettle();
    expect(h.writes, ['action:accept']);
    expect(find.byKey(const Key('incoming-call')), findsNothing);
    expect(find.text('Вызов #45984 · В пути'), findsOneWidget);

    // Confirm arrival from the navigation sheet.
    await tester.tap(find.byKey(const Key('nav-1')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationScreen), findsOneWidget);
    expectButton('step-arrive', 'Подтвердить прибытие');
    expect(find.byKey(const Key('step-transport')), findsNothing);
    await tester.tap(find.byKey(const Key('step-arrive')));
    await tester.pumpAndSettle();
    expect(h.writes, ['action:accept', 'action:arrive']);
    expectButton('step-transport', 'Пациент загружен');
    expectButton('step-complete', 'Завершить вызов');

    // Patient loaded from the call details.
    await tester.tap(find.byKey(const Key('nav-open-call')));
    await tester.pumpAndSettle();
    expect(find.byType(CallScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('step-transport')).last);
    await tester.pumpAndSettle();
    expect(h.writes, ['action:accept', 'action:arrive', 'action:transport']);
    expect(find.byKey(const Key('step-transport')), findsNothing);

    // Complete.
    await tester.tap(find.byKey(const Key('step-complete')).last);
    await tester.pumpAndSettle();
    expect(h.writes, ['action:accept', 'action:arrive', 'action:transport', 'action:complete']);
    expect(find.text('Нет активного вызова'), findsOneWidget);
    expectNoErrors(tester);
  });

  group('«Смена и статус»', () {
    testWidgets('one button follows the state machine (ambulance)', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.push(tester, '/shift');
      expect(find.byKey(const Key('status-title')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('status-card')), matching: find.text('Не на смене')),
        findsOneWidget,
      );
      expectButton('step-goOnDuty', 'Выйти на смену');
      expect(find.byKey(const Key('timeline-duty-pending')), findsOneWidget);

      await tester.tap(find.byKey(const Key('step-goOnDuty')));
      await tester.pumpAndSettle();
      expectButton('step-endShift', 'Завершить смену');
      expect(find.byKey(const Key('timeline-duty-active')), findsOneWidget);
      expect(find.text('Готов к вызовам'), findsOneWidget);

      h.api.assign();
      await h.notify(tester);
      expectButton('step-accept', 'Принять вызов');
      expect(find.byKey(const Key('step-endShift')), findsNothing);
      expect(find.text('Новый вызов #45984 ждёт подтверждения'), findsOneWidget);

      await tester.tap(find.byKey(const Key('step-accept')));
      await tester.pumpAndSettle();
      expectButton('step-arrive', 'Подтвердить прибытие');
      expect(find.byKey(const Key('timeline-accepted-done')), findsOneWidget);
      expect(find.byKey(const Key('timeline-en_route-active')), findsOneWidget);
      expect(find.text('К вызову #45984'), findsOneWidget);
      expect(find.text('3,1 км · 4 мин'), findsNWidgets(2)); // status card + active step

      await tester.tap(find.byKey(const Key('step-arrive')));
      await tester.pumpAndSettle();
      expectButton('step-transport', 'Пациент загружен');
      expectButton('step-complete', 'Завершить вызов');
      expect(find.byKey(const Key('timeline-on_scene-active')), findsOneWidget);
      expect(find.byKey(const Key('timeline-transport-pending')), findsOneWidget);

      await tester.tap(find.byKey(const Key('step-transport')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('step-transport')), findsNothing);
      expectButton('step-complete', 'Завершить вызов');
      expect(find.byKey(const Key('timeline-transport-active')), findsOneWidget);
      // The moment «Пациент загружен» was confirmed is shown on the timeline.
      expect(
        find.descendant(of: find.byKey(const Key('timeline-transport-active')), matching: find.text('14:45')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('step-complete')));
      await tester.pumpAndSettle();
      expectButton('step-endShift', 'Завершить смену');
      expect(find.text('Возвращение на базу'), findsWidgets);

      await tester.tap(find.byKey(const Key('step-endShift')));
      await tester.pumpAndSettle();
      expectButton('step-goOnDuty', 'Выйти на смену');
      expect(h.writes, [
        'shift:true',
        'action:accept',
        'action:arrive',
        'action:transport',
        'action:complete',
        'shift:false',
      ]);
      expectNoErrors(tester);
    });

    testWidgets('a fire crew has no transport step and neutral wording', (tester) async {
      final h = Harness(phase: 'assigned', service: ServiceType.fire);
      await h.pump(tester);
      await h.push(tester, '/shift');
      expect(find.text('Пациент загружен'), findsNothing);
      expect(find.byKey(const Key('timeline-transport-pending')), findsNothing);
      expect(find.byKey(const Key('timeline-done-pending')), findsOneWidget);

      await tester.tap(find.byKey(const Key('step-accept')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('step-arrive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('step-transport')), findsNothing);
      expect(find.textContaining('Пациент'), findsNothing);
      expectButton('step-complete', 'Завершить вызов');

      await tester.tap(find.byKey(const Key('step-complete')));
      await tester.pumpAndSettle();
      expect(h.writes, ['action:accept', 'action:arrive', 'action:complete']);
      expectButton('step-endShift', 'Завершить смену');
    });

    testWidgets('409 → snackbar with a Russian explanation, state re-fetched', (tester) async {
      final h = Harness(phase: 'en_route');
      await h.pump(tester);
      await h.push(tester, '/shift');
      // The dispatcher has meanwhile closed the call: the server is elsewhere.
      h.api.failAction = const ApiException(409, 'unit cannot go from available to on_scene');
      h.api.phase = 'available';
      final before = h.api.calls.where((c) => c == 'me').length;
      await tester.tap(find.byKey(const Key('step-arrive')));
      await tester.pumpAndSettle();
      expect(find.text('Подтвердить прибытие можно только после принятия вызова.'), findsOneWidget);
      expect(h.api.calls.where((c) => c == 'me').length, greaterThan(before));
      expectButton('step-endShift', 'Завершить смену');
    });

    testWidgets('ending the shift during a call is explained', (tester) async {
      final h = Harness(phase: 'available');
      await h.pump(tester);
      await h.push(tester, '/shift');
      h.api.failShift = const ApiException(409, 'unit is busy');
      await tester.tap(find.byKey(const Key('step-endShift')));
      await tester.pumpAndSettle();
      expect(find.text('Нельзя завершить смену, пока есть активный вызов.'), findsOneWidget);
    });

    testWidgets('network failure on a step', (tester) async {
      final h = Harness(phase: 'assigned');
      await h.pump(tester);
      await h.push(tester, '/shift');
      h.api.failAction = const ApiException.network();
      await tester.tap(find.byKey(const Key('step-accept')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет соединения с сервером'), findsOneWidget);
      expectButton('step-accept', 'Принять вызов');
    });
  });

  group('call details', () {
    testWidgets('address, caller with call button, description, triage facts', (tester) async {
      final h = Harness(phase: 'en_route');
      await h.pump(tester);
      await h.push(tester, '/call');
      expect(find.text('Вызов #45984'), findsOneWidget);
      expect(find.text('Экстренный'), findsOneWidget);
      expect(find.text('Экстренная помощь'), findsOneWidget);
      expect(find.text('Скорая помощь · В пути'), findsOneWidget);
      expect(find.text('ул. Назарбаева, 125, Алматы'), findsOneWidget);
      expect(find.text('Тест\n+7 701 000 11 22'), findsOneWidget);
      expect(find.text('Мужчина, около 60 лет, потерял сознание'), findsOneWidget);
      // Empty extra_info is hidden.
      expect(find.text('Дополнительная информация'), findsNothing);
      expectButton('step-arrive', 'Подтвердить прибытие');

      await tester.tap(find.byKey(const Key('call-caller')));
      await tester.pump();
      expect(h.dialled, ['+7 701 000 11 22']);
      await tester.tap(find.byKey(const Key('call-caller-icon')));
      await tester.pump();
      expect(h.dialled, hasLength(2));

      await tester.tap(find.text('Пострадавший'));
      await tester.pumpAndSettle();
      expect(find.text('Угроза жизни'), findsOneWidget);
      expect(find.text('Есть'), findsOneWidget);
      expect(find.text('60 лет'), findsOneWidget);
      expect(find.text('адрес, сколько пострадавших'), findsOneWidget);

      await tester.tap(find.text('Карта'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-map')), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('extra info is shown when present; other services say «Сведения»', (tester) async {
      final h = Harness(phase: 'on_scene', service: ServiceType.police)..api.extraInfo = 'Код въезда: 3587';
      await h.pump(tester);
      await h.push(tester, '/call');
      expect(find.text('Дополнительная информация'), findsOneWidget);
      expect(find.text('Код въезда: 3587'), findsOneWidget);
      expect(find.text('Пострадавший'), findsNothing);
      expect(find.text('Сведения'), findsOneWidget);
      expect(find.byKey(const Key('step-transport')), findsNothing);
      expectButton('step-complete', 'Завершить вызов');
    });

    for (final width in const [360.0, 430.0]) {
      testWidgets('fits $width px on scene with both buttons', (tester) async {
        final h = Harness(phase: 'on_scene');
        await h.pump(tester, size: Size(width, 700));
        await h.push(tester, '/call');
        expectButton('step-transport', 'Пациент загружен');
        expectButton('step-complete', 'Завершить вызов');
        expectNoErrors(tester);
        await h.go(tester, '/shift');
        expectNoErrors(tester);
      });
    }
  });
}
