import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_citizen/features/call/call_form_screen.dart';
import 'package:jardem_citizen/features/tracking/tracking_screen.dart';
import 'package:jardem_core/jardem_core.dart';

import 'support.dart';

// 1×1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<Harness> _openForm(WidgetTester tester, {String location = '/call/ambulance?category=emergency'}) async {
  final h = Harness();
  await h.pump(tester);
  await h.go(tester, location);
  expect(find.byType(CallFormScreen), findsOneWidget);
  return h;
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('call-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('call-submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('call form', () {
    testWidgets('layout: title, categories, fields prefilled, demo text', (tester) async {
      final h = await _openForm(tester);
      expect(find.text('Вызов скорой помощи'), findsOneWidget);
      expect(find.text('Экстренная'), findsOneWidget);
      expect(find.text('Плановая'), findsOneWidget);
      expect(find.text('Что произошло?'), findsOneWidget);
      expect(find.text('Опишите ситуацию…'), findsOneWidget);
      expect(find.text('Добавить фото / видео'), findsOneWidget);
      expect(find.text('Точный адрес'), findsOneWidget);
      expect(find.text('Контактный телефон'), findsOneWidget);
      expect(find.text('Вызвать скорую'), findsOneWidget);
      // Prefilled from the demo location and the signed-in user.
      expect(tester.widget<TextFormField>(find.byKey(const Key('call-address'))).controller!.text, kDemoAddress);
      expect(tester.widget<TextFormField>(find.byKey(const Key('call-phone'))).controller!.text, '+7 777 123 45 67');
      // Non-dismissible demo notice with a 112 button.
      expect(find.text('Демо-режим. В реальной экстренной ситуации звоните 112'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '112'));
      await tester.pumpAndSettle();
      expect(h.dialled, ['112']);
      expectNoErrors(tester);
    });

    testWidgets('each service has its own title and button', (tester) async {
      final h = await _openForm(tester, location: '/call/police');
      expect(find.text('Вызов полиции'), findsOneWidget);
      expect(find.text('Вызвать полицию'), findsOneWidget);
      await h.go(tester, '/call/fire');
      expect(find.text('Вызвать пожарных'), findsOneWidget);
      await h.go(tester, '/call/rescue');
      expect(find.text('Вызвать спасателей'), findsOneWidget);
    });

    testWidgets('validation blocks submit: bad phone and empty address', (tester) async {
      final h = await _openForm(tester);
      await tester.enterText(find.byKey(const Key('call-phone')), '+7 777 12');
      await tester.enterText(find.byKey(const Key('call-address')), ' ');
      await _submit(tester);
      expect(find.text('Введите номер в формате +7 XXX XXX XX XX'), findsOneWidget);
      expect(find.text('Укажите адрес, чтобы экипаж быстрее вас нашёл'), findsOneWidget);
      expect(h.api.created, isNull);
      expect(find.byType(CallFormScreen), findsOneWidget);

      // Fixing the fields lets the call through.
      await tester.enterText(find.byKey(const Key('call-phone')), '8 701 555 12 12');
      await tester.enterText(find.byKey(const Key('call-address')), 'пр. Абая, 10, кв. 5');
      await _submit(tester);
      expect(h.api.created, isNotNull);
    });

    testWidgets('submit sends category, point, address, description, phone → tracking', (tester) async {
      final h = await _openForm(tester);
      await tester.tap(find.text('Плановая'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('call-description')), '  Болит спина, нужна консультация ');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await _submit(tester);

      expect(h.api.created, {
        'category': 'planned',
        'at': kDemoPoint,
        'address': kDemoAddress,
        'description': 'Болит спина, нужна консультация',
        'phone': '+7 777 123 45 67',
      });
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(find.byType(CallFormScreen), findsNothing);
      expect(h.api.calls, contains('incident:inc-45831'));
    });

    testWidgets('description is debounced into one triage call; hint shows category, priority, missing', (
      tester,
    ) async {
      final h = await _openForm(tester, location: '/call/fire');
      await tester.enterText(find.byKey(const Key('call-description')), 'горит');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const Key('call-description')), 'горит квартира, много дыма');
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.api.calls.where((c) => c.startsWith('triage')), isEmpty, reason: 'still inside the debounce window');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(h.api.calls.where((c) => c.startsWith('triage')), ['triage:горит квартира, много дыма']);
      expect(find.byKey(const Key('triage-hint')), findsOneWidget);
      expect(find.text('Похоже на: Пожарные · Пожарные части'), findsOneWidget);
      expect(find.text('Экстренный'), findsOneWidget);
      expect(find.text('Уточните: адрес, есть ли люди внутри'), findsOneWidget);
      // Same service and category as selected → nothing to switch to.
      expect(find.byKey(const Key('triage-switch')), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('triage suggesting another service offers a one-tap switch', (tester) async {
      final h = await _openForm(tester);
      await tester.enterText(find.byKey(const Key('call-description')), 'горит квартира на третьем этаже');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('Сменить на: Пожарные части'), findsOneWidget);
      expect(find.text('Вызов скорой помощи'), findsOneWidget);

      await tester.tap(find.byKey(const Key('triage-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Вызов пожарных'), findsOneWidget);
      expect(find.text('Вызвать пожарных'), findsOneWidget);
      expect(find.byKey(const Key('triage-switch')), findsNothing);

      await _submit(tester);
      expect(h.api.created!['category'], 'fire_engine');
    });

    testWidgets('life threat is called out; short text clears the hint; triage failure is silent', (tester) async {
      final h = await _openForm(tester);
      h.api.triageResult = TriageResult.fromJson({
        'service': 'ambulance',
        'category': 'reanimation',
        'category_title': 'Реанимация',
        'priority': 1,
        'life_threat': true,
        'missing': ['address', 'victims_count'],
      });
      await tester.enterText(find.byKey(const Key('call-description')), 'не дышит');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.textContaining('Указана угроза жизни'), findsOneWidget);
      expect(find.text('Сменить на: Реанимация'), findsOneWidget);
      expect(find.text('Уточните: адрес, сколько пострадавших'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('call-description')), 'не');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('triage-hint')), findsNothing);

      h.api.failTriage = const ApiException(500, 'boom');
      await tester.enterText(find.byKey(const Key('call-description')), 'снова не дышит');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('triage-hint')), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('uncertain triage says so', (tester) async {
      final h = await _openForm(tester);
      h.api.triageResult = const TriageResult(uncertain: true, missing: ['what_happened']);
      await tester.enterText(find.byKey(const Key('call-description')), 'что-то случилось');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось определить категорию по описанию'), findsOneWidget);
      expect(find.byKey(const Key('triage-switch')), findsNothing);
    });

    testWidgets('422 → outside Almaty message; form stays usable', (tester) async {
      final h = await _openForm(tester);
      h.api.failCreate = const ApiException(422, 'the location is outside the Almaty service area');
      await _submit(tester);
      expect(find.byKey(const Key('call-error')), findsOneWidget);
      expect(find.textContaining('Адрес вне зоны обслуживания'), findsOneWidget);
      expect(find.byType(CallFormScreen), findsOneWidget);

      h.api.failCreate = null;
      await _submit(tester);
      expect(find.byType(TrackingScreen), findsOneWidget);
    });

    testWidgets('429 → three open calls message', (tester) async {
      final h = await _openForm(tester);
      h.api.failCreate = const ApiException(429, 'too many open incidents');
      await _submit(tester);
      expect(find.textContaining('У вас уже 3 активных вызова'), findsOneWidget);
    });

    testWidgets('network failure → connection message', (tester) async {
      final h = await _openForm(tester);
      h.api.failCreate = const ApiException.network();
      await _submit(tester);
      expect(find.textContaining('Нет соединения с сервером'), findsOneWidget);
    });

    test('createIncidentError', () {
      expect(createIncidentError(const ApiException(422, '')), contains('в пределах Алматы'));
      expect(createIncidentError(const ApiException(429, '')), contains('3 активных вызова'));
      expect(createIncidentError(const ApiException(500, '')), contains('Ошибка сервера (500)'));
      expect(createIncidentError(StateError('x')), 'Что-то пошло не так. Попробуйте ещё раз.');
    });

    testWidgets('picked media stay local, are listed and removable', (tester) async {
      final h = await _openForm(tester);
      h.mediaToPick = [PickedMedia(name: 'a.png', bytes: _png), const PickedMedia(name: 'clip.mp4')];
      await tester.tap(find.byKey(const Key('call-media')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
      expect(find.textContaining('в демо-версии фото и видео не отправляются'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('не отправляются'), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('fits 360 px wide phones', (tester) async {
      final h = Harness();
      await h.pump(tester, size: const Size(360, 640));
      await h.go(tester, '/call/ambulance');
      await tester.enterText(find.byKey(const Key('call-description')), 'горит квартира на третьем этаже');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expectNoErrors(tester);
    });
  });

  group('«Другое»', () {
    testWidgets('free text → triage → suggestion → call form with text', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('service-other')));
      await tester.pumpAndSettle();
      expect(find.text('Опишите, что случилось'), findsOneWidget);

      // Too short: no request.
      await tester.tap(find.byKey(const Key('other-analyse')));
      await tester.pumpAndSettle();
      expect(find.text('Опишите ситуацию хотя бы парой слов.'), findsOneWidget);
      expect(h.api.calls.where((c) => c.startsWith('triage')), isEmpty);

      await tester.enterText(find.byKey(const Key('other-text')), 'в подъезде сильный запах дыма');
      await tester.tap(find.byKey(const Key('other-analyse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('other-suggestion')), findsOneWidget);
      expect(find.text('Рекомендуем'), findsOneWidget);
      expect(find.text('Пожарные части'), findsOneWidget);
      expect(find.textContaining('есть ли люди внутри'), findsOneWidget);
      expectNoErrors(tester);

      await tester.tap(find.byKey(const Key('other-continue')));
      await tester.pumpAndSettle();
      expect(find.byType(CallFormScreen), findsOneWidget);
      expect(find.text('Вызов пожарных'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byKey(const Key('call-description'))).controller!.text,
        'в подъезде сильный запах дыма',
      );
      await _submit(tester);
      expect(h.api.created!['category'], 'fire_engine');
      expect(h.api.created!['description'], 'в подъезде сильный запах дыма');
    });

    testWidgets('uncertain triage → manual service choice', (tester) async {
      final h = Harness()..api.triageResult = const TriageResult(uncertain: true);
      await h.pump(tester);
      await h.go(tester, '/other');
      await tester.enterText(find.byKey(const Key('other-text')), 'непонятная ситуация');
      await tester.tap(find.byKey(const Key('other-analyse')));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось определить службу'), findsOneWidget);
      expect(find.byKey(const Key('other-suggestion')), findsNothing);
      await tester.ensureVisible(find.text('Полиция'));
      await tester.tap(find.text('Полиция'));
      await tester.pumpAndSettle();
      expect(find.text('Вызов полиции'), findsOneWidget);
    });

    testWidgets('triage error is shown', (tester) async {
      final h = Harness()..api.failTriage = const ApiException.network();
      await h.pump(tester);
      await h.go(tester, '/other');
      await tester.enterText(find.byKey(const Key('other-text')), 'что-то горит');
      await tester.tap(find.byKey(const Key('other-analyse')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет соединения'), findsOneWidget);
    });
  });
}
