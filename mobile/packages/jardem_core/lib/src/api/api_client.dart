import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/catalog.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/json.dart';
import '../models/meta.dart';
import '../models/responder.dart';
import '../models/route.dart';
import '../models/session.dart';
import '../models/traffic.dart';
import '../models/triage.dart';
import '../models/unit.dart';
import '../utils/geo.dart';
import 'api_exception.dart';

/// Typed client for the Jardem.ai REST API (see `docs/api.md`).
///
/// The [http.Client] is injectable so tests can pass a `MockClient`.
class ApiClient {
  ApiClient({required String baseUrl, http.Client? httpClient, this.token, this.timeout = const Duration(seconds: 15)})
    : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
      _http = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  /// Bearer token sent with every request when set.
  String? token;

  void close() => _http.close();

  // --- public ---------------------------------------------------------------

  Future<Health> health() async => Health.fromJson(asJson(await _get('/health')));

  Future<Meta> meta() async => Meta.fromJson(asJson(await _get('/meta')));

  Future<List<ServiceInfo>> catalog() async => ServiceInfo.listFromJson(await _get('/catalog'));

  Future<List<Department>> departments({ServiceType? service, LatLng? near, int? limit}) async => listOf(
    await _get('/departments', {'service': service?.id, ..._point(near), 'limit': limit}),
    Department.fromJson,
  );

  /// On-duty units; with [near]: free units first, then by ETA.
  Future<List<Unit>> units({ServiceType? service, String? category, LatLng? near, int? limit}) async =>
      Unit.listFromJson(
        await _get('/units', {'service': service?.id, 'category': category, ..._point(near), 'limit': limit}),
      );

  /// One unit; with [to] the response includes `route`, `eta_s`, `distance_m`.
  Future<Unit> unit(String id, {LatLng? to}) async =>
      Unit.fromJson(asJson(await _get('/units/${Uri.encodeComponent(id)}', _point(to))));

  Future<RouteResult> route(LatLng from, LatLng to, {String profile = 'emergency'}) async => RouteResult.fromJson(
    asJson(
      await _get('/route', {
        'from_lat': from.latitude,
        'from_lon': from.longitude,
        'to_lat': to.latitude,
        'to_lon': to.longitude,
        'profile': profile,
      }),
    ),
  );

  Future<TrafficData> traffic({GeoBounds? bbox, bool? includeFree}) async =>
      TrafficData.fromJson(asJson(await _get('/traffic', {'bbox': bbox?.toQuery(), 'include_free': includeFree})));

  Future<TriageResult> triage(String text) async =>
      TriageResult.fromJson(asJson(await _post('/triage', {'text': text})));

  Future<DispatchComparison> dispatchCompare({required String category, required LatLng at}) async =>
      DispatchComparison.fromJson(
        asJson(await _post('/dispatch/compare', {'category': category, 'lat': at.latitude, 'lon': at.longitude})),
      );

  Future<Stats> stats() async => Stats.fromJson(asJson(await _get('/stats')));

  // --- auth -----------------------------------------------------------------

  /// Signs a citizen in and stores the token on this client.
  Future<Session> loginCitizen({required String phone, String name = ''}) =>
      _login('/auth/citizen', {'phone': phone, 'name': name});

  Future<Session> loginResponder({required String login, required String pin}) =>
      _login('/auth/responder', {'login': login, 'pin': pin});

  Future<Session> loginDispatcher({String login = 'dispatcher', required String pin}) =>
      _login('/auth/dispatcher', {'login': login, 'pin': pin});

  Future<User> me() async => User.fromJson(asJson(await _get('/auth/me')));

  /// Ends the server-side session; for a crew this hands a simulated unit back to the simulator.
  Future<void> logout() async {
    await _post('/auth/logout');
  }

  Future<Session> _login(String path, Json body) async {
    final session = Session.fromJson(asJson(await _post(path, body)));
    token = session.token;
    return session;
  }

  // --- citizen --------------------------------------------------------------

  Future<Incident> createIncident({
    required String category,
    required LatLng at,
    String address = '',
    String description = '',
    String phone = '',
  }) async => Incident.fromJson(
    asJson(
      await _post('/incidents', {
        'category': category,
        'lat': at.latitude,
        'lon': at.longitude,
        'address': address,
        'description': description,
        'phone': phone,
      }),
    ),
  );

  Future<IncidentList> incidents() async => IncidentList.fromJson(asJson(await _get('/incidents')));

  Future<Incident> incident(String id) async =>
      Incident.fromJson(asJson(await _get('/incidents/${Uri.encodeComponent(id)}')));

  Future<Incident> cancelIncident(String id) async =>
      Incident.fromJson(asJson(await _post('/incidents/${Uri.encodeComponent(id)}/cancel')));

  // --- responder ------------------------------------------------------------

  Future<ResponderState> responderMe() async => ResponderState.fromJson(asJson(await _get('/responder/me')));

  Future<Json> responderShift({required bool onDuty}) async =>
      asJson(await _post('/responder/shift', {'on_duty': onDuty}));

  Future<Json> responderAction(ResponderAction action) async =>
      asJson(await _post('/responder/action', {'action': action.id}));

  Future<Json> responderLocation(LatLng at, {double? speedMps}) async =>
      asJson(await _post('/responder/location', {'lat': at.latitude, 'lon': at.longitude, 'speed_mps': ?speedMps}));

  Future<List<Message>> responderMessages() async => Message.listFromJson(await _get('/responder/messages'));

  Future<Message> sendResponderMessage(String text) async =>
      Message.fromJson(asJson(await _post('/responder/messages', {'text': text})));

  Future<List<Incident>> responderHistory() async => Incident.listFromJson(await _get('/responder/history'));

  Future<RoadClosure> reportClosure(LatLng at, {String reason = '', int minutes = 30}) async => RoadClosure.fromJson(
    asJson(
      await _post('/traffic/closures', {'lat': at.latitude, 'lon': at.longitude, 'reason': reason, 'minutes': minutes}),
    ),
  );

  Future<void> liftClosure(String id) => _send('DELETE', '/traffic/closures/${Uri.encodeComponent(id)}');

  // --- dispatcher -----------------------------------------------------------

  Future<Json> dispatchOverview() async => asJson(await _get('/dispatch/overview'));

  Future<Json> dispatchAssign({required String incidentId, required String unitId}) async =>
      asJson(await _post('/dispatch/assign', {'incident_id': incidentId, 'unit_id': unitId}));

  Future<Message> dispatchMessage({required String unitId, required String text}) async =>
      Message.fromJson(asJson(await _post('/dispatch/messages', {'unit_id': unitId, 'text': text})));

  /// Only the given settings are changed.
  Future<Json> dispatchSettings({
    String? strategy,
    bool? autoDispatch,
    double? simSpeed,
    double? callsPerHour,
    bool? hotspots,
  }) async => asJson(
    await _post('/dispatch/settings', {
      'strategy': ?strategy,
      'auto_dispatch': ?autoDispatch,
      'sim_speed': ?simSpeed,
      'calls_per_hour': ?callsPerHour,
      'hotspots': ?hotspots,
    }),
  );

  Future<TrafficHotspot> createHotspot(
    LatLng at, {
    double? radiusM,
    double? severity,
    int? minutes,
    String? kind,
  }) async => TrafficHotspot.fromJson(
    asJson(
      await _post('/traffic/hotspots', {
        'lat': at.latitude,
        'lon': at.longitude,
        'radius_m': ?radiusM,
        'severity': ?severity,
        'minutes': ?minutes,
        'kind': ?kind,
      }),
    ),
  );

  // --- transport ------------------------------------------------------------

  Map<String, Object?> _point(LatLng? p) => p == null ? const {} : {'lat': p.latitude, 'lon': p.longitude};

  Future<Object?> _get(String path, [Map<String, Object?> query = const {}]) => _send('GET', path, query: query);

  Future<Object?> _post(String path, [Json? body]) => _send('POST', path, body: body ?? const {});

  Future<Object?> _send(String method, String path, {Map<String, Object?> query = const {}, Json? body}) async {
    final params = {
      for (final e in query.entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
    final request = http.Request(method, uri)..headers['Accept'] = 'application/json';
    final bearer = token;
    if (bearer != null && bearer.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearer';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiException.network('timeout');
    } on http.ClientException catch (e) {
      throw ApiException.network(e.message);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.network(e.toString());
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, _detail(decoded, text));
    }
    return decoded;
  }

  /// FastAPI sends `{"detail": "…"}` or, for validation errors, a list of
  /// `{"msg": …}` objects.
  static String _detail(Object? decoded, String raw) {
    if (decoded is Map) {
      final d = decoded['detail'];
      if (d is String) return d;
      if (d is List) {
        return d.map((e) => e is Map ? (e['msg'] ?? e).toString() : e.toString()).join('; ');
      }
    }
    return raw;
  }
}
