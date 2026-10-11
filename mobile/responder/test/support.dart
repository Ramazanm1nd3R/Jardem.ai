import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/app.dart';
import 'package:jardem_responder/router.dart';
import 'package:jardem_responder/state/gps.dart';
import 'package:jardem_responder/state/providers.dart';
import 'package:jardem_responder/state/session.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
Map<String, dynamic> fixtureMap(String name) => (fixture(name) as Map).cast<String, dynamic>();

/// The moment every widget test runs at (local time).
final DateTime kTestNow = DateTime(2026, 10, 11, 14, 45);

const String kUnitId = 'ambulance-7-1';

/// In-memory backend with the crew state machine of the real API. Every call
/// is recorded in [calls]; payloads are the ones captured from the live API.
class FakeApi extends ApiClient {
  FakeApi() : super(baseUrl: 'http://fake.test/api/v1');

  final List<String> calls = [];

  /// Unit status id: off_duty / available / assigned / en_route / on_scene /
  /// transporting / returning.
  String phase = 'off_duty';
  ServiceType service = ServiceType.ambulance;
  String extraInfo = '';

  Object? failLogin;
  Object? failMe;
  Object? failAction;
  Object? failShift;
  Object? failSend;
  Object? failClosure;
  Object? failHistory;
  Object? failMessages;
  Object? failTraffic;

  List<Message> messages = Message.listFromJson(fixture('messages'));
  List<Incident> history = Incident.listFromJson(fixture('history'));
  List<RoadClosure> closures = [];
  final List<({LatLng at, double? speed})> locations = [];
  ({LatLng at, String reason, int minutes})? reported;
  int _closureSeq = 0;

  Never _throw(Object e) => throw e;

  /// A dispatcher assigns a call to this crew.
  void assign() => phase = 'assigned';

  Map<String, dynamic> meJson() {
    final json = fixtureMap(switch (phase) {
      'off_duty' => 'me_idle',
      'assigned' => 'me_assigned',
      'en_route' => 'me_en_route',
      'on_scene' => 'me_on_scene',
      'transporting' => 'me_transporting',
      _ => 'me_returning',
    });
    final unit = (json['unit'] as Map).cast<String, dynamic>()
      ..['status'] = phase
      ..['service'] = service.id;
    if (service != ServiceType.ambulance) unit['callsign'] = 'ПЧ №9';
    final assignment = json['assignment'];
    if (assignment is Map) {
      assignment['service'] = service.id;
      assignment['extra_info'] = extraInfo;
    }
    return json;
  }

  @override
  Future<Meta> meta() async {
    calls.add('meta');
    return Meta.fromJson(fixtureMap('meta'));
  }

  @override
  Future<Session> loginResponder({required String login, required String pin}) async {
    calls.add('login:$login:$pin');
    if (failLogin != null) _throw(failLogin!);
    final session = Session.fromJson(fixtureMap('session'));
    token = session.token;
    return session;
  }

  @override
  Future<ResponderState> responderMe() async {
    calls.add('me');
    if (failMe != null) _throw(failMe!);
    return ResponderState.fromJson(meJson());
  }

  @override
  Future<Json> responderShift({required bool onDuty}) async {
    calls.add('shift:$onDuty');
    if (failShift != null) _throw(failShift!);
    phase = onDuty ? 'available' : 'off_duty';
    return const {};
  }

  @override
  Future<Json> responderAction(ResponderAction action) async {
    calls.add('action:${action.id}');
    if (failAction != null) _throw(failAction!);
    final next = switch ((phase, action)) {
      ('assigned', ResponderAction.accept) => 'en_route',
      ('en_route', ResponderAction.arrive) => 'on_scene',
      ('on_scene', ResponderAction.transport) => 'transporting',
      ('on_scene' || 'transporting', ResponderAction.complete) => 'returning',
      _ => null,
    };
    if (next == null) _throw(ApiException(409, 'unit cannot go from $phase'));
    phase = next;
    return const {};
  }

  @override
  Future<Json> responderLocation(LatLng at, {double? speedMps}) async {
    calls.add('location');
    locations.add((at: at, speed: speedMps));
    return const {};
  }

  @override
  Future<List<Message>> responderMessages() async {
    calls.add('messages');
    if (failMessages != null) _throw(failMessages!);
    return [...messages];
  }

  @override
  Future<Message> sendResponderMessage(String text) async {
    calls.add('send:$text');
    if (failSend != null) _throw(failSend!);
    final message = Message(
      id: 'msg-${messages.length + 1}',
      unitId: kUnitId,
      sender: 'unit',
      author: 'Алексей Иванов',
      text: text,
      at: kTestNow.toUtc(),
    );
    messages = [...messages, message];
    return message;
  }

  @override
  Future<List<Incident>> responderHistory() async {
    calls.add('history');
    if (failHistory != null) _throw(failHistory!);
    return history;
  }

  @override
  Future<List<Unit>> units({ServiceType? service, String? category, LatLng? near, int? limit}) async {
    calls.add('units:${service?.id}');
    return [
      Unit(
        id: 'peer-1',
        service: service ?? ServiceType.ambulance,
        status: UnitStatus.available,
        lat: 43.26,
        lon: 76.95,
        free: true,
      ),
      Unit(
        id: kUnitId,
        service: service ?? ServiceType.ambulance,
        status: UnitStatus.available,
        lat: 43.28,
        lon: 76.99,
      ),
    ];
  }

  @override
  Future<RouteResult> route(LatLng from, LatLng to, {String profile = 'emergency'}) async {
    calls.add('route');
    return RouteResult.fromJson(fixtureMap('route'));
  }

  @override
  Future<TrafficData> traffic({GeoBounds? bbox, bool? includeFree}) async {
    calls.add('traffic');
    if (failTraffic != null) _throw(failTraffic!);
    final json = fixtureMap('traffic');
    json['closures'] = [
      for (final c in closures) {'id': c.id, 'lat': c.lat, 'lon': c.lon, 'reason': c.reason},
    ];
    return TrafficData.fromJson(json);
  }

  @override
  Future<RoadClosure> reportClosure(LatLng at, {String reason = '', int minutes = 30}) async {
    calls.add('closure:$reason');
    if (failClosure != null) _throw(failClosure!);
    reported = (at: at, reason: reason, minutes: minutes);
    final c = RoadClosure(id: 'cl-${++_closureSeq}', lat: at.latitude, lon: at.longitude, reason: reason);
    closures = [...closures, c];
    // Like the real API: the response carries the id but no coordinates.
    return RoadClosure(id: c.id, lat: 0, lon: 0);
  }

  @override
  Future<void> liftClosure(String id) async {
    calls.add('lift:$id');
    if (!closures.any((c) => c.id == id)) throw const ApiException(404, 'closure not found');
    closures = closures.where((c) => c.id != id).toList();
  }
}

class FakeFixSource implements FixSource {
  GpsFix? fix;
  int requests = 0;

  @override
  Future<GpsFix?> current() async {
    requests++;
    return fix;
  }
}

/// Everything a widget test needs to drive the app.
class Harness {
  Harness({this.signedIn = true, String phase = 'off_duty', ServiceType service = ServiceType.ambulance}) {
    api
      ..phase = phase
      ..service = service;
  }

  final bool signedIn;
  final api = FakeApi();
  final events = StreamController<RealtimeEvent>.broadcast();
  final gps = FakeFixSource();
  final dialled = <String>[];
  final navigated = <LatLng>[];
  bool navigatorOpens = true;
  Map<String, Object> extraPrefs = {};
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    JardemMap.tilesEnabled = false;
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // Stops the pulsing map pin so pumpAndSettle can finish.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    SharedPreferences.setMockInitialValues({
      if (signedIn) kSessionKey: jsonEncode(fixtureMap('session')),
      ...extraPrefs,
    });
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
          realtimeEventsProvider.overrideWithValue(events.stream),
          clockProvider.overrideWithValue(() => kTestNow),
          fixSourceProvider.overrideWithValue(gps),
          dialerProvider.overrideWithValue((number) async {
            dialled.add(number);
            return true;
          }),
          navigatorOpenerProvider.overrideWithValue((to) async {
            navigated.add(to);
            return navigatorOpens;
          }),
        ],
        child: const JardemResponderApp(),
      ),
    );
    // Providers live in the widget tree, so their timers die with it.
    container = ProviderScope.containerOf(tester.element(find.byType(JardemResponderApp)));
    addTearDown(events.close);
    await tester.pumpAndSettle();
  }

  /// Navigates without going through the UI.
  Future<void> go(WidgetTester tester, String location) async {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  Future<void> push(WidgetTester tester, String location) async {
    unawaited(container.read(routerProvider).push(location));
    await tester.pumpAndSettle();
  }

  /// A realtime notification about this crew, then let the refresh land.
  Future<void> notify(WidgetTester tester, [RealtimeEvent? event]) async {
    events.add(event ?? const IncidentUpdated(incidentId: 'inc-45984', unitIds: [kUnitId]));
    await tester.pumpAndSettle();
  }

  /// Only the state-changing requests, in order.
  List<String> get writes => [
    for (final c in api.calls)
      if (c.startsWith('action:') ||
          c.startsWith('shift:') ||
          c.startsWith('send:') ||
          c.startsWith('closure:') ||
          c.startsWith('lift:'))
        c,
  ];
}

/// The label inside the button with [key].
void expectButton(String key, String label) {
  expect(find.byKey(Key(key)), findsOneWidget, reason: 'button $key');
  expect(
    find.descendant(of: find.byKey(Key(key)), matching: find.text(label)),
    findsOneWidget,
    reason: '$key label',
  );
}

/// Fails the test on layout overflow or any other framework error.
void expectNoErrors(WidgetTester tester) => expect(tester.takeException(), isNull);
