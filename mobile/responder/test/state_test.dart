import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/steps.dart';
import 'package:jardem_responder/state/closures.dart';
import 'package:jardem_responder/state/crew.dart';
import 'package:jardem_responder/state/gps.dart';
import 'package:jardem_responder/state/map.dart';
import 'package:jardem_responder/state/messages.dart';
import 'package:jardem_responder/state/providers.dart';
import 'package:jardem_responder/state/session.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

class _Env {
  _Env(this.container, this.api, this.events, this.prefs, this.gps);
  final ProviderContainer container;
  final FakeApi api;
  final StreamController<RealtimeEvent> events;
  final SharedPreferences prefs;
  final FakeFixSource gps;
}

Future<_Env> _env({String phase = 'available', Map<String, Object> prefs = const {}, bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues({
    if (signedIn)
      kSessionKey:
          '{"token":"t","user":{"id":"resp-demo","role":"responder","name":"Алексей Иванов","unit_id":"$kUnitId"}}',
    ...prefs,
  });
  final p = await SharedPreferences.getInstance();
  final api = FakeApi()..phase = phase;
  final events = StreamController<RealtimeEvent>.broadcast();
  final gps = FakeFixSource();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(p),
      apiClientProvider.overrideWithValue(api),
      realtimeEventsProvider.overrideWithValue(events.stream),
      clockProvider.overrideWithValue(() => kTestNow),
      fixSourceProvider.overrideWithValue(gps),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(events.close);
  return _Env(container, api, events, p, gps);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('session', () {
    test('corrupted or incomplete stored sessions are ignored', () async {
      for (final raw in ['not json', '[]', '{"token":"","user":{"id":"x"}}', '{"token":"t","user":{}}']) {
        SharedPreferences.setMockInitialValues({kSessionKey: raw});
        expect(readStoredSession(await SharedPreferences.getInstance()), isNull, reason: raw);
      }
      SharedPreferences.setMockInitialValues({});
      expect(readStoredSession(await SharedPreferences.getInstance()), isNull);
    });

    test('sign-in stores the session and the token; sign-out clears both', () async {
      final e = await _env(signedIn: false);
      expect(e.container.read(sessionProvider), isNull);
      await e.container.read(sessionProvider.notifier).signIn(login: ' smp7 ', pin: ' 1234 ');
      expect(e.api.calls, ['login:smp7:1234']);
      expect(e.container.read(sessionProvider)!.user.unitId, kUnitId);
      expect(readStoredSession(e.prefs)!.token, 'test-token');
      await e.container.read(sessionProvider.notifier).signOut();
      expect(e.container.read(sessionProvider), isNull);
      expect(e.api.token, isNull);
      expect(e.prefs.getString(kSessionKey), isNull);
    });

    test('a failed sign-in stores nothing', () async {
      final e = await _env(signedIn: false);
      e.api.failLogin = const ApiException(401, 'wrong login or PIN');
      await expectLater(
        e.container.read(sessionProvider.notifier).signIn(login: 'smp7', pin: '0'),
        throwsA(isA<ApiException>()),
      );
      expect(e.prefs.getString(kSessionKey), isNull);
    });

    test('sign-in error wording', () {
      expect(signInError(const ApiException(401, 'x')), 'Неверный логин или PIN-код.');
      expect(signInError(const ApiException.network()), contains('Нет соединения'));
      expect(signInError(const ApiException(500, 'x')), contains('Ошибка сервера'));
    });
  });

  group('crew', () {
    test('loads /responder/me for the signed-in unit', () async {
      final e = await _env();
      expect(e.container.read(crewProvider).loading, isTrue);
      await _settle();
      final crew = e.container.read(crewProvider);
      expect(crew.unit!.id, kUnitId);
      expect(crew.status, UnitStatus.available);
      expect(crew.assignment, isNull);
      expect(crew.incoming, isNull);
      expect(e.container.read(crewProvider.notifier).unitId, kUnitId);
    });

    test('signed out: no requests at all', () async {
      final e = await _env(signedIn: false);
      e.container.read(crewProvider);
      e.container.read(chatProvider);
      await _settle();
      expect(e.api.calls, isEmpty);
    });

    test('refreshes on events about this unit only', () async {
      final e = await _env();
      e.container.read(crewProvider);
      await _settle();
      int loads() => e.api.calls.where((c) => c == 'me').length;
      expect(loads(), 1);
      e.events.add(const UnitUpdated(unitId: 'fire-9-1'));
      e.events.add(const IncidentUpdated(incidentId: 'inc-1', unitIds: ['fire-9-1']));
      e.events.add(const MessageCreated('fire-9-1'));
      e.events.add(const TrafficUpdated());
      await _settle();
      expect(loads(), 1);
      e.events.add(const UnitUpdated(unitId: kUnitId));
      await _settle();
      expect(loads(), 2);
      e.events.add(const MessageCreated(kUnitId));
      await _settle();
      expect(loads(), 3);
    });

    test('an assignment makes `incoming` non-null until accepted', () async {
      final e = await _env();
      e.container.read(crewProvider);
      await _settle();
      e.api.assign();
      e.events.add(const IncidentUpdated(incidentId: 'inc-45984', unitIds: [kUnitId]));
      await _settle();
      expect(e.container.read(crewProvider).incoming!.number, 45984);
      await e.container.read(crewProvider.notifier).perform(CrewStep.accept);
      final crew = e.container.read(crewProvider);
      expect(crew.status, UnitStatus.enRoute);
      expect(crew.incoming, isNull);
      expect(crew.assignment!.id, 'inc-45984');
      // Events about the current incident now count too.
      final before = e.api.calls.where((c) => c == 'me').length;
      e.events.add(const IncidentUpdated(incidentId: 'inc-45984'));
      await _settle();
      expect(e.api.calls.where((c) => c == 'me').length, before + 1);
    });

    test('units.moved patches the position but never the status', () async {
      final e = await _env(phase: 'en_route');
      e.container.read(crewProvider);
      await _settle();
      e.events.add(
        const UnitsMoved([
          UnitPosition(id: 'fire-9-1', service: ServiceType.fire, lat: 1, lon: 1),
          UnitPosition(
            id: kUnitId,
            service: ServiceType.ambulance,
            status: UnitStatus.onScene,
            lat: 43.28,
            lon: 76.98,
            heading: 90,
          ),
        ]),
      );
      await _settle();
      final crew = e.container.read(crewProvider);
      expect(crew.unit!.position, const LatLng(43.28, 76.98));
      expect(crew.unit!.heading, 90);
      expect(crew.status, UnitStatus.enRoute);
      expect(crew.assignment, isNotNull);
      expect(e.api.calls.where((c) => c == 'me'), hasLength(1));
    });

    test('perform: rethrows, re-fetches, and records the transport time', () async {
      final e = await _env(phase: 'on_scene');
      final notifier = e.container.read(crewProvider.notifier);
      await _settle();
      await notifier.perform(CrewStep.transport);
      expect(e.container.read(crewProvider).transportAt, {'inc-45984': kTestNow});
      expect(e.container.read(crewProvider).status, UnitStatus.transporting);

      // 409: accept is impossible while transporting.
      final loads = e.api.calls.where((c) => c == 'me').length;
      await expectLater(
        notifier.perform(CrewStep.accept),
        throwsA(isA<ApiException>().having((x) => x.isConflict, 'conflict', isTrue)),
      );
      expect(e.api.calls.where((c) => c == 'me').length, loads + 1);
      expect(e.container.read(crewProvider).transportAt, hasLength(1));

      await notifier.perform(CrewStep.complete);
      await notifier.perform(CrewStep.endShift);
      expect(e.api.calls.where((c) => c.startsWith('shift') || c.startsWith('action')), [
        'action:transport',
        'action:accept',
        'action:complete',
        'shift:false',
      ]);
      expect(e.container.read(crewProvider).status, UnitStatus.offDuty);
    });

    test('a failed refresh keeps the last data; 401 signs out', () async {
      final e = await _env();
      final notifier = e.container.read(crewProvider.notifier);
      await _settle();
      e.api.failMe = const ApiException.network();
      await notifier.refresh();
      expect(e.container.read(crewProvider).unit, isNotNull);
      expect(e.container.read(crewProvider).error, isA<ApiException>());
      e.api.failMe = const ApiException(401, 'expired');
      await notifier.refresh();
      await _settle();
      expect(e.container.read(sessionProvider), isNull);
    });
  });

  group('chat', () {
    test('send appends once even when the reload already brought the message', () async {
      final e = await _env();
      final chat = e.container.read(chatProvider.notifier);
      await _settle();
      expect(e.container.read(chatProvider).messages, hasLength(3));
      expect(await chat.send('  '), isFalse);
      expect(await chat.send(' Принял '), isTrue);
      await chat.refresh();
      final ids = e.container.read(chatProvider).messages!.map((m) => m.id).toList();
      expect(ids, ['msg-1', 'msg-2', 'msg-3', 'msg-4']);
    });

    test('markRead persists per unit and survives a restart', () async {
      final e = await _env();
      e.container.read(chatProvider);
      await _settle();
      expect(e.container.read(chatProvider).unread, 2);
      e.container.read(chatProvider.notifier).markRead();
      expect(e.container.read(chatProvider).unread, 0);
      final stored = e.prefs.getString('$kChatReadKey.$kUnitId');
      expect(DateTime.parse(stored!), DateTime.parse('2026-10-11T09:39:47.829087+00:00'));

      final again = await _env(prefs: {'$kChatReadKey.$kUnitId': stored});
      again.container.read(chatProvider);
      await _settle();
      expect(again.container.read(chatProvider).unread, 0);
    });

    test('a load error keeps the messages already shown', () async {
      final e = await _env();
      final chat = e.container.read(chatProvider.notifier);
      await _settle();
      e.api.failMessages = const ApiException.network();
      await chat.refresh();
      expect(e.container.read(chatProvider).messages, hasLength(3));
      expect(e.container.read(chatProvider).error, isNotNull);
    });
  });

  group('closures', () {
    test('lifting a closure the server already dropped (404) still forgets it', () async {
      final e = await _env(
        prefs: {
          kClosuresKey: <String>['cl-5'],
        },
      );
      final c = e.container.read(myClosuresProvider.notifier);
      expect(e.container.read(myClosuresProvider), {'cl-5'});
      await c.lift('cl-5');
      expect(e.container.read(myClosuresProvider), isEmpty);
      expect(e.prefs.getStringList(kClosuresKey), isEmpty);
    });

    test('report remembers the id returned by the server', () async {
      final e = await _env();
      await e.container.read(myClosuresProvider.notifier).report(const LatLng(43.25, 76.95), 'Затор');
      expect(e.container.read(myClosuresProvider), {'cl-1'});
      expect(e.api.reported, (at: const LatLng(43.25, 76.95), reason: 'Затор', minutes: 30));
    });
  });

  group('navigation route', () {
    test('requested only while heading to a call', () async {
      final e = await _env(phase: 'available');
      e.container.read(crewProvider);
      await _settle();
      final sub = e.container.listen(navRouteProvider('inc-45984'), (_, _) {});
      addTearDown(sub.close);
      await _settle();
      expect(e.api.calls, isNot(contains('route')));
      expect(sub.read(), isNull);

      e.api.phase = 'en_route';
      await e.container.read(crewProvider.notifier).refresh();
      await e.container.read(navRouteProvider('inc-45984').notifier).refresh();
      expect(sub.read()!.sections, isNotEmpty);

      // Arrived: the line disappears.
      e.api.phase = 'on_scene';
      await e.container.read(crewProvider.notifier).refresh();
      await e.container.read(navRouteProvider('inc-45984').notifier).refresh();
      expect(sub.read(), isNull);
    });
  });

  group('gps', () {
    test('off by default; nothing is read or sent', () async {
      final e = await _env();
      e.container.read(crewProvider);
      await _settle();
      expect(e.container.read(gpsProvider).sharing, isFalse);
      await e.container.read(gpsProvider.notifier).tick();
      expect(e.gps.requests, 0);
      expect(e.api.locations, isEmpty);
    });

    test('accepted, rejected and missing fixes', () async {
      final e = await _env();
      e.container.read(crewProvider);
      await _settle();
      final gps = e.container.read(gpsProvider.notifier);
      await gps.setSharing(true);
      expect(e.container.read(gpsProvider).lastFixAccepted, isFalse); // no fix yet
      e.gps.fix = const GpsFix(LatLng(43.25, 76.95), speedMps: 200);
      await gps.tick();
      expect(e.api.locations, [(at: const LatLng(43.25, 76.95), speed: null)]);
      expect(e.container.read(gpsProvider).lastFixAccepted, isTrue);
      expect(e.container.read(gpsProvider).sent, 1);
      e.gps.fix = const GpsFix(LatLng(55.75, 37.62));
      await gps.tick();
      expect(e.api.locations, hasLength(1));
      expect(e.container.read(gpsProvider).lastFixAccepted, isFalse);
      expect(e.container.read(gpsProvider).sent, 1);
      await gps.setSharing(false);
      expect(e.container.read(gpsProvider).sharing, isFalse);
    });
  });
}
