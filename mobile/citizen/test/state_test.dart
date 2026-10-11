import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_citizen/state/incidents.dart';
import 'package:jardem_citizen/state/location.dart';
import 'package:jardem_citizen/state/providers.dart';
import 'package:jardem_citizen/state/session.dart';
import 'package:jardem_citizen/state/units.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

class _ExpiredApi extends FakeApi {
  @override
  Future<User> me() async => throw const ApiException(401, 'expired');
}

void main() {
  group('session', () {
    Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('stored session is restored and the token applied', () async {
      final prefs = await prefsWith({
        kSessionKey: jsonEncode({
          'token': 'tok',
          'user': {'id': 'cit-1', 'name': 'Айдос', 'phone': '+7 777 123 45 67'},
        }),
      });
      final api = FakeApi();
      final controller = SessionController(api, prefs);
      expect(controller.state!.user.name, 'Айдос');
      expect(api.token, 'tok');
      await pumpEventQueue();
      expect(api.calls, ['me']);
      expect(controller.state, isNotNull);
    });

    test('corrupted or incomplete storage means signed out', () async {
      expect(readStoredSession(await prefsWith({})), isNull);
      expect(readStoredSession(await prefsWith({kSessionKey: '{oops'})), isNull);
      expect(readStoredSession(await prefsWith({kSessionKey: '[1,2]'})), isNull);
      expect(readStoredSession(await prefsWith({kSessionKey: '{"token":"","user":{"id":"x"}}'})), isNull);
      expect(readStoredSession(await prefsWith({kSessionKey: '{"token":"t","user":{}}'})), isNull);
      final api = FakeApi();
      expect(SessionController(api, await prefsWith({kSessionKey: 'junk'})).state, isNull);
      expect(api.calls, isEmpty);
    });

    test('a token rejected with 401 is dropped', () async {
      final prefs = await prefsWith({
        kSessionKey: jsonEncode({
          'token': 'old',
          'user': {'id': 'cit-1'},
        }),
      });
      final api = _ExpiredApi();
      final controller = SessionController(api, prefs);
      await pumpEventQueue();
      expect(controller.state, isNull);
      expect(prefs.getString(kSessionKey), isNull);
      expect(api.token, isNull);
    });

    test('signIn persists; signOut clears', () async {
      final prefs = await prefsWith({});
      final api = FakeApi();
      final controller = SessionController(api, prefs);
      await controller.signIn(phone: '87771234567', name: '  Айдос ');
      expect(api.calls, ['login:+7 777 123 45 67:Айдос']);
      expect(controller.state!.user.phone, '+7 777 123 45 67');
      expect(readStoredSession(prefs)!.token, 'test-token-citizen');

      await controller.signOut();
      expect(controller.state, isNull);
      expect(readStoredSession(prefs), isNull);
      expect(api.token, isNull);
    });
  });

  group('location', () {
    ProviderContainer container(FakeLocationService service) {
      final c = ProviderContainer(
        overrides: [locationServiceProvider.overrideWithValue(service), apiClientProvider.overrideWithValue(FakeApi())],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('starts at the demo point', () {
      final state = container(FakeLocationService()).read(locationProvider);
      expect(state.point, kDemoPoint);
      expect(state.isDemo, isTrue);
      expect(state.label, kDemoAddress);
      expect(state.addressPrefill, kDemoAddress);
      expect(state.reason, isNull);
    });

    test('no fix → demo with a reason', () async {
      final c = container(FakeLocationService());
      final state = await c.read(locationProvider.notifier).locate();
      expect(state.isDemo, isTrue);
      expect(state.reason, 'Геолокация недоступна — показан демо-адрес.');
    });

    test('fix outside the service area → demo with a reason', () async {
      final c = container(FakeLocationService(const LatLng(55.75, 37.62)));
      final state = await c.read(locationProvider.notifier).locate();
      expect(state.isDemo, isTrue);
      expect(state.point, kDemoPoint);
      expect(state.reason, contains('вне Алматы'));
    });

    test('fix inside Almaty is used; the address is left for the user', () async {
      final c = container(FakeLocationService(const LatLng(43.2565, 76.9285)));
      final state = await c.read(locationProvider.notifier).locate();
      expect(state.source, LocationSource.gps);
      expect(state.point, const LatLng(43.2565, 76.9285));
      expect(state.label, 'Геопозиция: 43.2565, 76.9285');
      expect(state.addressPrefill, '');
      expect(c.read(locationProvider).point, state.point);
    });

    test('manual pin: accepted inside, refused outside', () {
      final c = container(FakeLocationService());
      final notifier = c.read(locationProvider.notifier);
      expect(notifier.setManual(const LatLng(43.30, 76.90)), isTrue);
      expect(c.read(locationProvider).source, LocationSource.manual);
      expect(c.read(locationProvider).label, 'Точка на карте: 43.3000, 76.9000');
      expect(notifier.setManual(const LatLng(44.0, 76.90)), isFalse);
      expect(c.read(locationProvider).point, const LatLng(43.30, 76.90));
    });
  });

  group('UnitsController', () {
    test('loads, patches positions from units.moved, ignores strangers', () async {
      final api = FakeApi();
      final events = StreamController<RealtimeEvent>.broadcast();
      final controller = UnitsController(api, events.stream, const UnitsQuery(service: ServiceType.ambulance));
      addTearDown(controller.dispose);
      expect(controller.state.isLoading, isTrue);
      await pumpEventQueue();
      final before = controller.state.value!;
      expect(before, hasLength(3));

      events.add(const UnitsMoved([UnitPosition(id: 'nobody', service: ServiceType.fire, lat: 1, lon: 2)]));
      await pumpEventQueue();
      expect(identical(controller.state.value, before), isTrue, reason: 'no rebuild for unrelated units');

      events.add(
        const UnitsMoved([
          UnitPosition(
            id: 'ambulance-1-3',
            service: ServiceType.ambulance,
            status: UnitStatus.enRoute,
            lat: 43.24,
            lon: 76.94,
            heading: 45,
          ),
        ]),
      );
      await pumpEventQueue();
      final after = controller.state.value!;
      expect(after[1].position, const LatLng(43.24, 76.94));
      expect(after[1].status, UnitStatus.enRoute);
      expect(after[1].free, isFalse);
      expect(after[0].position, before[0].position);
      expect(after[2].position, before[2].position);
    });

    test('error on first load; silent refresh keeps the last list', () async {
      final api = FakeApi()..failUnits = const ApiException.network();
      final events = StreamController<RealtimeEvent>.broadcast();
      final controller = UnitsController(api, events.stream, const UnitsQuery());
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(controller.state.hasError, isTrue);

      api.failUnits = null;
      await controller.refresh();
      expect(controller.state.value, hasLength(3));

      api.failUnits = const ApiException.network();
      await controller.refresh(silent: true);
      expect(controller.state.hasError, isFalse);
      expect(controller.state.value, hasLength(3));
    });

    test('query equality', () {
      const a = UnitsQuery(service: ServiceType.fire, category: 'forest', near: kDemoPoint, limit: 5);
      const b = UnitsQuery(service: ServiceType.fire, category: 'forest', near: kDemoPoint, limit: 5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == const UnitsQuery(service: ServiceType.fire, category: 'forest', near: kDemoPoint, limit: 6), isFalse);
      expect(a == const UnitsQuery(service: ServiceType.fire, category: 'engine', near: kDemoPoint, limit: 5), isFalse);
      expect(
        a == const UnitsQuery(service: ServiceType.police, category: 'forest', near: kDemoPoint, limit: 5),
        isFalse,
      );
      expect(a == const UnitsQuery(service: ServiceType.fire, category: 'forest', limit: 5), isFalse);
    });
  });

  test('TrackingState.copyWith keeps data on errors and can clear them', () {
    final incident = incidentWith('en_route');
    final state = TrackingState(incident: incident, unit: incident.primaryUnit);
    final failed = state.copyWith(error: 'boom', loading: false);
    expect(failed.incident, same(incident));
    expect(failed.unit, same(incident.primaryUnit));
    expect(failed.error, 'boom');
    expect(failed.copyWith(clearError: true).error, isNull);
  });
}
