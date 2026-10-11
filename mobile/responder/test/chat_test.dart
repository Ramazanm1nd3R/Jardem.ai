import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';

import 'support.dart';

void main() {
  Future<Harness> open(WidgetTester tester, {String phase = 'available'}) async {
    final h = Harness(phase: phase);
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('bubbles with author and time, quick replies', (tester) async {
    final h = await open(tester);
    expect(find.text('Связь с диспетчером'), findsOneWidget);
    expect(find.text('СМП №7, подтвердите приём вызова #45982.'), findsOneWidget);
    expect(find.text('Принял'), findsWidgets);
    final at = formatClock(DateTime.parse('2026-10-11T09:39:21.603125+00:00'));
    expect(find.text('Диспетчер · $at'), findsWidgets);
    expect(find.textContaining('Алексей Иванов · '), findsOneWidget);
    for (final r in ['Принял', 'В пути', 'На месте']) {
      expect(find.byKey(Key('quick-$r')), findsOneWidget);
    }
    expect(h.api.calls, contains('messages'));
    expectNoErrors(tester);
  });

  testWidgets('typing and sending posts the message and shows it', (tester) async {
    final h = await open(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), '  Выезжаем, 4 минуты  ');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(h.writes, ['send:Выезжаем, 4 минуты']);
    expect(find.text('Выезжаем, 4 минуты'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, isEmpty);
  });

  testWidgets('blank input sends nothing', (tester) async {
    final h = await open(tester);
    await tester.enterText(find.byKey(const Key('chat-input')), '   ');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(h.writes, isEmpty);
  });

  testWidgets('quick reply sends in one tap and keeps the draft', (tester) async {
    final h = await open(tester, phase: 'en_route');
    await tester.enterText(find.byKey(const Key('chat-input')), 'черновик');
    await tester.tap(find.byKey(const Key('quick-В пути')));
    await tester.pumpAndSettle();
    expect(h.writes, ['send:В пути']);
    expect(find.byKey(const Key('msg-msg-4')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, 'черновик');
  });

  testWidgets('message.created for this unit reloads the chat; other units are ignored', (tester) async {
    final h = await open(tester);
    int loads() => h.api.calls.where((c) => c == 'messages').length;
    final before = loads();
    h.events.add(const MessageCreated('fire-9-1'));
    await tester.pumpAndSettle();
    expect(loads(), before);

    h.api.messages = [
      ...h.api.messages,
      Message(
        id: 'msg-9',
        unitId: kUnitId,
        sender: 'dispatcher',
        author: 'Диспетчер',
        text: 'Ориентировочное время прибытия?',
        at: kTestNow.toUtc(),
      ),
    ];
    h.events.add(const MessageCreated(kUnitId));
    await tester.pumpAndSettle();
    expect(loads(), before + 1);
    expect(find.text('Ориентировочное время прибытия?'), findsOneWidget);
  });

  testWidgets('a new dispatcher message raises the badge on other tabs, reading clears it', (tester) async {
    final h = await open(tester);
    await tester.tap(find.byKey(const Key('nav-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bell-badge')), findsNothing);

    h.api.messages = [
      ...h.api.messages,
      Message(id: 'msg-9', unitId: kUnitId, sender: 'dispatcher', text: 'Приём', at: kTestNow.toUtc()),
    ];
    h.events.add(const MessageCreated(kUnitId));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('bell-badge')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('nav-3')), matching: find.text('1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bell-badge')), findsNothing);
  });

  testWidgets('send failure keeps the text and explains', (tester) async {
    final h = await open(tester);
    h.api.failSend = const ApiException.network();
    await tester.enterText(find.byKey(const Key('chat-input')), 'Принял');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сообщение не отправлено'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-input'))).controller!.text, 'Принял');
  });

  testWidgets('«Аудио» and «Каналы» are honest placeholders', (tester) async {
    await open(tester);
    await tester.tap(find.text('Аудио'));
    await tester.pumpAndSettle();
    expect(find.text('В разработке'), findsOneWidget);
    expect(find.textContaining('Голосовая связь'), findsOneWidget);
    expect(find.byKey(const Key('chat-input')), findsNothing);
    await tester.tap(find.text('Каналы'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Групповые каналы'), findsOneWidget);
  });

  testWidgets('empty and error states', (tester) async {
    final h = Harness(phase: 'available')..api.messages = [];
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('Сообщений пока нет'), findsOneWidget);

    final h2 = Harness(phase: 'available')..api.failMessages = const ApiException.network();
    await h2.pump(tester);
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    h2.api.failMessages = null;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('СМП №7, подтвердите приём вызова #45982.'), findsOneWidget);
  });

  testWidgets('fits 360 px', (tester) async {
    final h = Harness(phase: 'on_scene');
    await h.pump(tester, size: const Size(360, 640));
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expectNoErrors(tester);
  });
}
