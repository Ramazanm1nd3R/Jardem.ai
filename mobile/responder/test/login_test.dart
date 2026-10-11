import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/features/home/home_screen.dart';
import 'package:jardem_responder/features/login/login_screen.dart';
import 'package:jardem_responder/state/session.dart';

import 'support.dart';

void main() {
  testWidgets('login screen: slogan, button, demo disclaimer', (tester) async {
    final h = Harness(signedIn: false);
    await h.pump(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Работаем\nради жизни'), findsOneWidget);
    expect(find.text('Войти в систему'), findsOneWidget);
    expect(find.text('Сменить пользователя'), findsOneWidget);
    expect(find.text('Демо-режим: вызовы и экипажи смоделированы'), findsOneWidget);
    expect(h.api.calls, isNot(contains('me')));
    expectNoErrors(tester);
  });

  for (final size in const [Size(360, 640), Size(430, 932)]) {
    testWidgets('login screen fits ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      final h = Harness(signedIn: false);
      await h.pump(tester, size: size);
      expect(find.text('Войти в систему'), findsOneWidget);
      expectNoErrors(tester);
    });
  }

  testWidgets('sign in with login + PIN → home, session persisted', (tester) async {
    final h = Harness(signedIn: false);
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('login-open')));
    await tester.pumpAndSettle();
    expect(find.text('Демо: smp7 / 1234'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-field')), ' smp7 ');
    await tester.enterText(find.byKey(const Key('pin-field')), '1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(h.api.calls, contains('login:smp7:1234'));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Алексей Иванов'), findsWidgets);
    expect(h.api.token, 'test-token');
    expect(readStoredSession(h.prefs)!.user.unitId, 'ambulance-7-1');
    expect(h.prefs.getString(kLastLoginKey), 'smp7');
    expectNoErrors(tester);
  });

  testWidgets('wrong PIN (401) → clear Russian error, stays on the sheet', (tester) async {
    final h = Harness(signedIn: false)..api.failLogin = const ApiException(401, 'wrong login or PIN');
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('login-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-field')), 'smp7');
    await tester.enterText(find.byKey(const Key('pin-field')), '0000');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Неверный логин или PIN-код.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(readStoredSession(h.prefs), isNull);

    // The second attempt succeeds and clears the error.
    h.api.failLogin = null;
    await tester.enterText(find.byKey(const Key('pin-field')), '1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('no network on sign-in', (tester) async {
    final h = Harness(signedIn: false)..api.failLogin = const ApiException.network();
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('login-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-field')), 'smp7');
    await tester.enterText(find.byKey(const Key('pin-field')), '1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нет соединения'), findsOneWidget);
  });

  testWidgets('empty fields are rejected before any request', (tester) async {
    final h = Harness(signedIn: false);
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('login-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Введите логин экипажа'), findsOneWidget);
    expect(find.text('Введите PIN-код'), findsOneWidget);
    expect(h.api.calls.where((c) => c.startsWith('login')), isEmpty);
  });

  testWidgets('the last login is remembered; «Сменить пользователя» forgets it', (tester) async {
    final h = Harness(signedIn: false)..extraPrefs = {kLastLoginKey: 'fire-9-1'};
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('login-open')));
    await tester.pumpAndSettle();
    expect(find.text('fire-9-1'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login-switch')));
    await tester.pumpAndSettle();
    expect(h.prefs.getString(kLastLoginKey), isNull);
    expect(find.text('fire-9-1'), findsNothing);
    expect(find.byKey(const Key('login-field')), findsOneWidget);
  });

  testWidgets('a stored session opens the home screen; an expired token returns to login', (tester) async {
    final h = Harness();
    await h.pump(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(h.api.token, 'test-token');

    h.api.failMe = const ApiException(401, 'expired');
    await h.notify(tester, const UnitUpdated(unitId: kUnitId));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(readStoredSession(h.prefs), isNull);
    expect(h.api.token, isNull);
  });
}
