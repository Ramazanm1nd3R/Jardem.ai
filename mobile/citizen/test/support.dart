import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_citizen/app.dart';
import 'package:jardem_citizen/features/call/call_form_screen.dart';
import 'package:jardem_citizen/router.dart';
import 'package:jardem_citizen/state/location.dart';
import 'package:jardem_citizen/state/providers.dart';
import 'package:jardem_citizen/state/session.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
Map<String, dynamic> fixtureMap(String name) => (fixture(name) as Map).cast<String, dynamic>();

/// The live `POST /incidents` payload with a different status / fields.
Incident incidentWith(String status, {Map<String, dynamic> extra = const {}}) {
  final json = fixtureMap('incident_created')
    ..['status'] = status
    ..addAll(extra);
  if (status == 'resolved' || status == 'cancelled') json['units'] = <dynamic>[];
  if (status == 'on_scene' || status == 'resolved') {
    json['first_arrival_s'] = 173;
    json['eta_s'] = 0;
  }
  return Incident.fromJson(json);
}

/// In-memory backend. Every call is recorded in [calls]; responses default to
/// payloads captured from the live API and can be replaced per test.
class FakeApi extends ApiClient {
  FakeApi() : super(baseUrl: 'http://fake.test/api/v1');

  final List<String> calls = [];

  Object? failCatalog;
  Object? failUnits;
  Object? failTraffic;
  Object? failTriage;
  Object? failCreate;
  Object? failCancel;
  Object? failIncident;
  Object? failIncidents;
  Object? failLogin;

  TriageResult? triageResult;
  IncidentList? incidentList;
  Incident? currentIncident;
  List<Unit>? unitList;

  /// Arguments of the last `createIncident` call.
  Map<String, Object?>? created;
  UnitsRequest? lastUnits;

  Never _throw(Object e) => throw e;

  @override
  Future<Meta> meta() async {
    calls.add('meta');
    return Meta.fromJson(fixtureMap('meta'));
  }

  @override
  Future<List<ServiceInfo>> catalog() async {
    calls.add('catalog');
    if (failCatalog != null) _throw(failCatalog!);
    return ServiceInfo.listFromJson(fixture('catalog'));
  }

  @override
  Future<List<Unit>> units({ServiceType? service, String? category, LatLng? near, int? limit}) async {
    calls.add('units');
    lastUnits = (service: service, category: category, near: near, limit: limit);
    if (failUnits != null) _throw(failUnits!);
    final all = unitList ?? Unit.listFromJson(fixture('units'));
    return [
      for (final u in all)
        if (service == null || u.service == service) u,
    ];
  }

  @override
  Future<Unit> unit(String id, {LatLng? to}) async {
    calls.add('unit:$id');
    return Unit.fromJson(fixtureMap('unit_detail')..['id'] = id);
  }

  @override
  Future<TrafficData> traffic({GeoBounds? bbox, bool? includeFree}) async {
    calls.add('traffic');
    if (failTraffic != null) _throw(failTraffic!);
    return TrafficData.fromJson(fixtureMap('traffic'));
  }

  @override
  Future<TriageResult> triage(String text) async {
    calls.add('triage:$text');
    if (failTriage != null) _throw(failTriage!);
    return triageResult ?? TriageResult.fromJson(fixtureMap('triage'));
  }

  @override
  Future<Session> loginCitizen({required String phone, String name = ''}) async {
    calls.add('login:$phone:$name');
    if (failLogin != null) _throw(failLogin!);
    final session = Session.fromJson(
      fixtureMap('session')..['user'] = {'id': 'cit-1', 'role': 'citizen', 'name': name, 'phone': phone},
    );
    token = session.token;
    return session;
  }

  @override
  Future<User> me() async {
    calls.add('me');
    return const User(id: 'cit-1', name: 'Айдос', phone: '+7 777 123 45 67');
  }

  @override
  Future<Incident> createIncident({
    required String category,
    required LatLng at,
    String address = '',
    String description = '',
    String phone = '',
  }) async {
    calls.add('createIncident');
    created = {'category': category, 'at': at, 'address': address, 'description': description, 'phone': phone};
    if (failCreate != null) _throw(failCreate!);
    return currentIncident ??= incidentWith('assigned');
  }

  @override
  Future<IncidentList> incidents() async {
    calls.add('incidents');
    if (failIncidents != null) _throw(failIncidents!);
    return incidentList ?? const IncidentList();
  }

  @override
  Future<Incident> incident(String id) async {
    calls.add('incident:$id');
    if (failIncident != null) _throw(failIncident!);
    return currentIncident ?? incidentWith('assigned');
  }

  @override
  Future<Incident> cancelIncident(String id) async {
    calls.add('cancel:$id');
    if (failCancel != null) _throw(failCancel!);
    return currentIncident = incidentWith('cancelled');
  }
}

typedef UnitsRequest = ({ServiceType? service, String? category, LatLng? near, int? limit});

class FakeLocationService implements LocationService {
  FakeLocationService([this.fix]);
  LatLng? fix;
  int requests = 0;

  @override
  Future<LatLng?> current() async {
    requests++;
    return fix;
  }
}

/// Everything a widget test needs to drive the app.
class Harness {
  Harness({this.signedIn = true, LatLng? gpsFix}) : location = FakeLocationService(gpsFix);

  final bool signedIn;
  final api = FakeApi();
  final events = StreamController<RealtimeEvent>.broadcast();
  final FakeLocationService location;
  final dialled = <String>[];
  bool dialSucceeds = true;
  List<PickedMedia> mediaToPick = const [];
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
      if (signedIn)
        kSessionKey: jsonEncode({
          'token': 'stored-token',
          'user': {'id': 'cit-1', 'role': 'citizen', 'name': 'Айдос Сабденов', 'phone': '+7 777 123 45 67'},
        }),
    });
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
          realtimeEventsProvider.overrideWithValue(events.stream),
          locationServiceProvider.overrideWithValue(location),
          dialerProvider.overrideWithValue((number) async {
            dialled.add(number);
            return dialSucceeds;
          }),
          mediaPickerProvider.overrideWithValue(() async => mediaToPick),
        ],
        child: const JardemCitizenApp(),
      ),
    );
    // Providers live in the widget tree, so their timers die with it.
    container = ProviderScope.containerOf(tester.element(find.byType(JardemCitizenApp)));
    addTearDown(events.close);
    await tester.pumpAndSettle();
  }

  /// Navigates without going through the UI.
  ///
  /// Pass `settle: false` for screens that show an endless spinner.
  Future<void> go(WidgetTester tester, String location, {bool settle = true}) async {
    container.read(routerProvider).go(location);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }
}

/// Fails the test on layout overflow or any other framework error.
void expectNoErrors(WidgetTester tester) => expect(tester.takeException(), isNull);
