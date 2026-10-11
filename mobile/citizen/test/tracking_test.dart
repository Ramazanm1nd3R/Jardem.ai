import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_citizen/features/tracking/call_stepper.dart';
import 'package:jardem_citizen/features/tracking/tracking_screen.dart';
import 'package:jardem_core/jardem_core.dart';

import 'support.dart';

Future<Harness> _open(
  WidgetTester tester,
  String status, {
  Map<String, dynamic> extra = const {},
  bool settle = true,
}) async {
  final h = Harness();
  h.api.currentIncident = incidentWith(status, extra: extra);
  await h.pump(tester);
  await h.go(tester, '/tracking/inc-45831', settle: settle);
  expect(find.byType(TrackingScreen), findsOneWidget);
  return h;
}

/// Phases of the four stepper dots, read from their keys.
List<String> _steps(WidgetTester tester) => [
  for (var i = 0; i < 4; i++)
    for (final phase in StepPhase.values)
      if (tester.any(find.byKey(Key('step-$i-${phase.name}')))) phase.name,
];

void main() {
  group('stepper reflects the incident status', () {
    testWidgets('labels', (tester) async {
      await _open(tester, 'assigned');
      for (final label in ['Принят', 'Экипаж выехал', 'В пути', 'Прибытие']) {
        expect(find.descendant(of: find.byType(CallStepper), matching: find.text(label)), findsOneWidget);
      }
      expectNoErrors(tester);
    });

    testWidgets('new', (tester) async {
      // Waiting for a crew shows a spinner, so the screen never settles.
      await _open(tester, 'new', extra: {'units': <dynamic>[]}, settle: false);
      expect(_steps(tester), ['done', 'pending', 'pending', 'pending']);
      expect(find.text('Вызов принят'), findsOneWidget);
      expect(find.text('Подбираем ближайший свободный экипаж…'), findsOneWidget);
    });

    testWidgets('assigned', (tester) async {
      await _open(tester, 'assigned');
      expect(_steps(tester), ['done', 'pending', 'pending', 'pending']);
      expect(find.text('Экипаж назначен'), findsOneWidget);
    });

    testWidgets('en_route', (tester) async {
      await _open(tester, 'en_route');
      expect(_steps(tester), ['done', 'done', 'active', 'pending']);
      expect(find.text('Экипаж в пути'), findsOneWidget);
    });

    testWidgets('on_scene', (tester) async {
      await _open(tester, 'on_scene');
      expect(_steps(tester), ['done', 'done', 'done', 'done']);
      expect(find.text('Экипаж на месте'), findsNWidgets(2)); // title + summary
      expect(find.text('Время прибытия: 3 мин'), findsOneWidget);
    });

    testWidgets('resolved', (tester) async {
      await _open(tester, 'resolved');
      expect(_steps(tester), ['done', 'done', 'done', 'done']);
      expect(find.text('Вызов завершён'), findsNWidgets(2));
      expect(find.text('Экипаж прибыл за 3 мин'), findsOneWidget);
      expect(find.text('На главную'), findsOneWidget);
      expect(find.byKey(const Key('tracking-cancel')), findsNothing);
    });

    testWidgets('cancelled', (tester) async {
      await _open(tester, 'cancelled');
      expect(_steps(tester), ['done', 'pending', 'pending', 'pending']);
      expect(find.text('Вызов отменён'), findsNWidgets(2));
    });
  });

  testWidgets('crew card, ETA chip, route and actions while en route', (tester) async {
    final h = await _open(tester, 'en_route');
    expect(find.text('Подстанция №1'), findsOneWidget);
    expect(find.text('Скорая помощь • Экстренная помощь'), findsOneWidget);
    expect(find.text('Гос. номер: 527 TK 02'), findsOneWidget);
    final chip = find.byKey(const Key('eta-chip'));
    expect(find.descendant(of: chip, matching: find.text('2 мин')), findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('1,8 км')), findsOneWidget);
    expect(find.byType(HighlightedUnitPin), findsOneWidget);
    expect(find.byType(MyLocationDot), findsOneWidget);
    expect(find.text('Позвонить'), findsOneWidget);
    expect(find.text('Написать'), findsOneWidget);
    expectNoErrors(tester);

    await tester.tap(find.byKey(const Key('tracking-dial')));
    await tester.pumpAndSettle();
    expect(h.dialled, ['103']);
  });

  testWidgets('«Написать» explains that chat is not available in the demo', (tester) async {
    await _open(tester, 'en_route');
    await tester.tap(find.byKey(const Key('tracking-chat')));
    await tester.pumpAndSettle();
    expect(find.text('Чат с экипажем'), findsOneWidget);
    expect(find.textContaining('В демо-версии переписка с экипажем недоступна'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.text('Чат с экипажем'), findsNothing);
  });

  testWidgets('5 s poll picks up a new status', (tester) async {
    final h = await _open(tester, 'assigned');
    expect(_steps(tester), ['done', 'pending', 'pending', 'pending']);
    final before = h.api.calls.where((c) => c.startsWith('incident:')).length;

    h.api.currentIncident = incidentWith('en_route');
    await tester.pump(const Duration(seconds: 4));
    expect(_steps(tester)[2], 'pending', reason: 'not polled yet');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_steps(tester), ['done', 'done', 'active', 'pending']);
    expect(h.api.calls.where((c) => c.startsWith('incident:')).length, before + 1);
  });

  testWidgets('incident.updated event refreshes immediately; other incidents are ignored', (tester) async {
    final h = await _open(tester, 'en_route');
    final before = h.api.calls.where((c) => c.startsWith('incident:')).length;

    h.events.add(const IncidentUpdated(incidentId: 'inc-other', status: IncidentStatus.onScene));
    await tester.pump();
    await tester.pump();
    expect(h.api.calls.where((c) => c.startsWith('incident:')).length, before);

    h.api.currentIncident = incidentWith('on_scene');
    h.events.add(const IncidentUpdated(incidentId: 'inc-45831', status: IncidentStatus.onScene));
    await tester.pumpAndSettle();
    expect(_steps(tester), ['done', 'done', 'done', 'done']);
    expect(find.byKey(const Key('tracking-summary')), findsOneWidget);
    expect(find.byKey(const Key('eta-chip')), findsNothing);
  });

  testWidgets('units.moved for our crew triggers a refresh', (tester) async {
    final h = await _open(tester, 'en_route');
    await tester.pump(const Duration(seconds: 1)); // past the 0.9 s throttle
    final before = h.api.calls.where((c) => c.startsWith('incident:')).length;
    h.events.add(const UnitsMoved([UnitPosition(id: 'someone-else', service: ServiceType.fire)]));
    await tester.pump();
    expect(h.api.calls.where((c) => c.startsWith('incident:')).length, before);
    h.events.add(const UnitsMoved([UnitPosition(id: 'ambulance-1-2', service: ServiceType.ambulance)]));
    await tester.pump();
    expect(h.api.calls.where((c) => c.startsWith('incident:')).length, before + 1);
  });

  testWidgets('the crew stays on the card after the incident closes', (tester) async {
    final h = await _open(tester, 'en_route');
    h.api.currentIncident = incidentWith('resolved');
    h.events.add(const IncidentUpdated(incidentId: 'inc-45831'));
    await tester.pumpAndSettle();
    expect(find.text('Вызов завершён'), findsNWidgets(2));
    expect(find.text('Подстанция №1'), findsOneWidget);
    expect(find.byType(HighlightedUnitPin), findsNothing);
    // Closed incidents are no longer polled.
    final before = h.api.calls.length;
    await tester.pump(const Duration(seconds: 11));
    expect(h.api.calls.length, before);
  });

  group('cancel', () {
    testWidgets('confirm dialog → cancelled', (tester) async {
      final h = await _open(tester, 'assigned');
      await tester.tap(find.byKey(const Key('tracking-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Отменить вызов?'), findsOneWidget);

      // Dismissing keeps the call.
      await tester.tap(find.text('Не отменять'));
      await tester.pumpAndSettle();
      expect(h.api.calls.where((c) => c.startsWith('cancel')), isEmpty);

      await tester.tap(find.byKey(const Key('tracking-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(h.api.calls, contains('cancel:inc-45831'));
      expect(find.text('Вызов отменён'), findsWidgets);
      expect(find.byKey(const Key('tracking-cancel')), findsNothing);
    });

    testWidgets('409 once the crew is on scene', (tester) async {
      final h = await _open(tester, 'en_route');
      h.api.failCancel = const ApiException(409, 'crew already on scene');
      h.api.currentIncident = incidentWith('on_scene');
      await tester.tap(find.byKey(const Key('tracking-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Экипаж уже на месте — отменить вызов нельзя.'), findsOneWidget);
      // The screen refreshed to the real state and no longer offers cancel.
      expect(_steps(tester), ['done', 'done', 'done', 'done']);
      expect(find.byKey(const Key('tracking-cancel')), findsNothing);
    });

    testWidgets('not offered once on scene', (tester) async {
      await _open(tester, 'on_scene');
      expect(find.byKey(const Key('tracking-cancel')), findsNothing);
    });
  });

  group('errors', () {
    testWidgets('initial load failure → retry', (tester) async {
      final h = Harness()..api.failIncident = const ApiException.network();
      await h.pump(tester);
      await h.go(tester, '/tracking/inc-45831');
      expect(find.text('Не удалось загрузить'), findsOneWidget);
      h.api.failIncident = null;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.byType(CallStepper), findsOneWidget);
    });

    testWidgets('refresh failure keeps the last data and shows a stale banner', (tester) async {
      final h = await _open(tester, 'en_route');
      h.api.failIncident = const ApiException.network();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.textContaining('данные могут быть неактуальны'), findsOneWidget);
      expect(find.text('Подстанция №1'), findsOneWidget);

      h.api.failIncident = null;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.textContaining('данные могут быть неактуальны'), findsNothing);
    });
  });

  testWidgets('back from a directly opened tracking screen goes to «Вызовы»', (tester) async {
    await _open(tester, 'en_route');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(TrackingScreen), findsNothing);
    expect(find.text('Нет активных вызовов'), findsOneWidget);
  });

  testWidgets('fits 360 px wide phones', (tester) async {
    final h = Harness();
    h.api.currentIncident = incidentWith('on_scene');
    await h.pump(tester, size: const Size(360, 640));
    await h.go(tester, '/tracking/inc-45831');
    expectNoErrors(tester);
  });
}
