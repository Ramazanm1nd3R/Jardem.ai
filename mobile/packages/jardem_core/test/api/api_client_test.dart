import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../fixtures.dart';

const _base = 'http://api.test/api/v1';
const _json = {'content-type': 'application/json; charset=utf-8'};

http.Response _ok(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: _json);

/// Client whose every request is recorded and answered with [reply].
(ApiClient, List<http.Request>) _client(FutureOr<http.Response> Function(http.Request) reply, {String? token}) {
  final seen = <http.Request>[];
  final api = ApiClient(
    baseUrl: _base,
    token: token,
    httpClient: MockClient((r) async {
      seen.add(r);
      return reply(r);
    }),
  );
  return (api, seen);
}

void main() {
  group('requests', () {
    test('GET /meta hits the right URL without auth', () async {
      final (api, seen) = _client((_) => _ok(fixture('meta')));
      final meta = await api.meta();
      expect(meta.city, 'Алматы');
      expect(seen.single.method, 'GET');
      expect(seen.single.url.toString(), '$_base/meta');
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
      expect(seen.single.headers['Accept'], 'application/json');
    });

    test('a trailing slash in the base URL is ignored', () async {
      final seen = <Uri>[];
      final api = ApiClient(
        baseUrl: '$_base/',
        httpClient: MockClient((r) async {
          seen.add(r.url);
          return _ok(fixture('health'));
        }),
      );
      expect((await api.health()).ok, isTrue);
      expect(seen.single.toString(), '$_base/health');
    });

    test('bearer token is sent when set and dropped when cleared', () async {
      final (api, seen) = _client((_) => _ok(fixture('me')), token: 'abc');
      await api.me();
      expect(seen.last.headers['Authorization'], 'Bearer abc');
      api.token = null;
      await api.me();
      expect(seen.last.headers.containsKey('Authorization'), isFalse);
      api.token = '';
      await api.me();
      expect(seen.last.headers.containsKey('Authorization'), isFalse);
    });

    test('units: query parameters, nulls omitted', () async {
      final (api, seen) = _client((_) => _ok(fixture('units')));
      final units = await api.units(
        service: ServiceType.ambulance,
        category: 'emergency',
        near: const LatLng(43.2445, 76.9457),
        limit: 3,
      );
      expect(units, hasLength(3));
      expect(seen.single.url.path, '/api/v1/units');
      expect(seen.single.url.queryParameters, {
        'service': 'ambulance',
        'category': 'emergency',
        'lat': '43.2445',
        'lon': '76.9457',
        'limit': '3',
      });

      await api.units();
      expect(seen.last.url.toString(), '$_base/units');
    });

    test('unit with a destination', () async {
      final (api, seen) = _client((_) => _ok(fixture('unit_detail')));
      final unit = await api.unit('ambulance-1-2', to: const LatLng(43.2445, 76.9457));
      expect(unit.route, isNotEmpty);
      expect(seen.single.url.path, '/api/v1/units/ambulance-1-2');
      expect(seen.single.url.queryParameters, {'lat': '43.2445', 'lon': '76.9457'});
    });

    test('departments, route, traffic, stats, catalog', () async {
      final (api, seen) = _client((r) {
        final name = r.url.pathSegments.last;
        return _ok(fixture(name));
      });
      expect(await api.departments(service: ServiceType.fire, near: kDemoPoint, limit: 2), hasLength(2));
      expect(seen.last.url.queryParameters, {'service': 'fire', 'lat': '43.2445', 'lon': '76.9457', 'limit': '2'});

      final route = await api.route(const LatLng(43.26, 76.93), kDemoPoint, profile: 'car');
      expect(route.distanceM, 3049);
      expect(seen.last.url.queryParameters, {
        'from_lat': '43.26',
        'from_lon': '76.93',
        'to_lat': '43.2445',
        'to_lon': '76.9457',
        'profile': 'car',
      });
      await api.route(const LatLng(43.26, 76.93), kDemoPoint);
      expect(seen.last.url.queryParameters['profile'], 'emergency');

      final traffic = await api.traffic(bbox: const GeoBounds(43.1, 76.7, 43.4, 77.1), includeFree: true);
      expect(traffic.index, 2);
      expect(seen.last.url.queryParameters, {'bbox': '43.1,76.7,43.4,77.1', 'include_free': 'true'});
      await api.traffic();
      expect(seen.last.url.hasQuery, isFalse);

      expect((await api.stats()).departments, 44);
      expect(await api.catalog(), hasLength(4));
    });

    test('triage posts JSON with a UTF-8 body', () async {
      final (api, seen) = _client((_) => _ok(fixture('triage')));
      final result = await api.triage('горит квартира');
      expect(result.category, 'fire_engine');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.toString(), '$_base/triage');
      expect(seen.single.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(utf8.decode(seen.single.bodyBytes)), {'text': 'горит квартира'});
    });

    test('loginCitizen stores the token for later calls', () async {
      final (api, seen) = _client((r) => _ok(fixture(r.url.path.endsWith('/citizen') ? 'session' : 'incidents')));
      final session = await api.loginCitizen(phone: '+7 777 123 45 67', name: 'Айдос');
      expect(session.user.name, 'Айдос');
      expect(seen.single.url.path, '/api/v1/auth/citizen');
      expect(jsonDecode(seen.single.body), {'phone': '+7 777 123 45 67', 'name': 'Айдос'});
      expect(api.token, 'test-token-citizen');

      await api.incidents();
      expect(seen.last.headers['Authorization'], 'Bearer test-token-citizen');
    });

    test('responder and dispatcher logins', () async {
      final (api, seen) = _client((_) => _ok(fixture('rsession')));
      final session = await api.loginResponder(login: 'smp7', pin: '1234');
      expect(session.user.unitId, 'ambulance-7-1');
      expect(seen.last.url.path, '/api/v1/auth/responder');
      expect(jsonDecode(seen.last.body), {'login': 'smp7', 'pin': '1234'});
      expect(api.token, 'test-token-responder');

      await api.loginDispatcher(pin: '1234');
      expect(seen.last.url.path, '/api/v1/auth/dispatcher');
      expect(jsonDecode(seen.last.body), {'login': 'dispatcher', 'pin': '1234'});
    });

    test('createIncident body and 201 response', () async {
      final (api, seen) = _client((_) => _ok(fixture('incident_created'), 201), token: 't');
      final incident = await api.createIncident(
        category: 'emergency',
        at: kDemoPoint,
        address: kDemoAddress,
        description: 'человек потерял сознание',
        phone: '+7 777 123 45 67',
      );
      expect(incident.id, 'inc-45831');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/api/v1/incidents');
      expect(jsonDecode(seen.single.body), {
        'category': 'emergency',
        'lat': 43.2445,
        'lon': 76.9457,
        'address': 'ул. Назарбаева, 125, Алматы',
        'description': 'человек потерял сознание',
        'phone': '+7 777 123 45 67',
      });
    });

    test('incident, cancel', () async {
      final (api, seen) = _client((_) => _ok(fixture('incident')), token: 't');
      expect((await api.incident('inc-45831')).status, IncidentStatus.assigned);
      expect(seen.last.method, 'GET');
      expect(seen.last.url.path, '/api/v1/incidents/inc-45831');
      await api.cancelIncident('inc-45831');
      expect(seen.last.method, 'POST');
      expect(seen.last.url.path, '/api/v1/incidents/inc-45831/cancel');
    });

    test('ids are percent-encoded', () async {
      final (api, seen) = _client((_) => _ok(fixture('incident')));
      await api.incident('a/b c');
      expect(seen.single.url.toString(), '$_base/incidents/a%2Fb%20c');
    });

    test('responder endpoints', () async {
      final (api, seen) = _client((r) {
        if (r.url.path.endsWith('/responder/me')) return _ok(fixture('responder_me'));
        if (r.method == 'GET') return _ok([]);
        if (r.url.path.endsWith('/messages')) return _ok({'id': 'm1', 'text': 'ок', 'sender': 'unit'});
        if (r.url.path.endsWith('/closures')) return _ok({'id': 'c1', 'lat': 43.2, 'lon': 76.9, 'reason': 'ДТП'}, 201);
        return _ok({'ok': true});
      }, token: 'r');

      expect((await api.responderMe()).unit.id, 'ambulance-7-1');
      expect(seen.last.headers['Authorization'], 'Bearer r');

      await api.responderShift(onDuty: true);
      expect(seen.last.url.path, '/api/v1/responder/shift');
      expect(jsonDecode(seen.last.body), {'on_duty': true});

      await api.responderAction(ResponderAction.arrive);
      expect(seen.last.url.path, '/api/v1/responder/action');
      expect(jsonDecode(seen.last.body), {'action': 'arrive'});

      await api.responderLocation(kDemoPoint, speedMps: 12.5);
      expect(seen.last.url.path, '/api/v1/responder/location');
      expect(jsonDecode(seen.last.body), {'lat': 43.2445, 'lon': 76.9457, 'speed_mps': 12.5});
      await api.responderLocation(kDemoPoint);
      expect(jsonDecode(seen.last.body), {'lat': 43.2445, 'lon': 76.9457});

      expect(await api.responderMessages(), isEmpty);
      expect(seen.last.method, 'GET');
      expect(seen.last.url.path, '/api/v1/responder/messages');

      expect((await api.sendResponderMessage('ок')).text, 'ок');
      expect(seen.last.method, 'POST');
      expect(jsonDecode(utf8.decode(seen.last.bodyBytes)), {'text': 'ок'});

      expect(await api.responderHistory(), isEmpty);
      expect(seen.last.url.path, '/api/v1/responder/history');

      final closure = await api.reportClosure(kDemoPoint, reason: 'ДТП', minutes: 45);
      expect(closure.id, 'c1');
      expect(seen.last.url.path, '/api/v1/traffic/closures');
      expect(jsonDecode(utf8.decode(seen.last.bodyBytes)), {
        'lat': 43.2445,
        'lon': 76.9457,
        'reason': 'ДТП',
        'minutes': 45,
      });

      await api.liftClosure('c1');
      expect(seen.last.method, 'DELETE');
      expect(seen.last.url.path, '/api/v1/traffic/closures/c1');
      expect(seen.last.body, isEmpty);
    });

    test('dispatcher endpoints', () async {
      final (api, seen) = _client((r) {
        if (r.url.path.endsWith('/hotspots')) return _ok({'id': 'h1', 'lat': 43.2, 'lon': 76.9, 'kind': 'accident'});
        if (r.url.path.endsWith('/compare')) {
          return _ok({
            'picks': {
              'jardem': ['u1'],
            },
            'candidates': [],
          });
        }
        if (r.url.path.endsWith('/dispatch/messages')) return _ok({'id': 'm', 'sender': 'dispatcher'});
        return _ok({'ok': true});
      }, token: 'd');

      expect(await api.dispatchOverview(), {'ok': true});
      expect(seen.last.url.path, '/api/v1/dispatch/overview');

      await api.dispatchAssign(incidentId: 'inc-1', unitId: 'u1');
      expect(jsonDecode(seen.last.body), {'incident_id': 'inc-1', 'unit_id': 'u1'});

      expect((await api.dispatchMessage(unitId: 'u1', text: 'hi')).fromDispatcher, isTrue);
      expect(jsonDecode(seen.last.body), {'unit_id': 'u1', 'text': 'hi'});

      await api.dispatchSettings(strategy: 'nearest', simSpeed: 2);
      expect(seen.last.url.path, '/api/v1/dispatch/settings');
      expect(jsonDecode(seen.last.body), {'strategy': 'nearest', 'sim_speed': 2.0});
      await api.dispatchSettings(autoDispatch: false, callsPerHour: 30, hotspots: true);
      expect(jsonDecode(seen.last.body), {'auto_dispatch': false, 'calls_per_hour': 30.0, 'hotspots': true});

      expect((await api.createHotspot(kDemoPoint, kind: 'accident', minutes: 10)).label, 'ДТП');
      expect(jsonDecode(seen.last.body), {'lat': 43.2445, 'lon': 76.9457, 'minutes': 10, 'kind': 'accident'});

      final cmp = await api.dispatchCompare(category: 'emergency', at: kDemoPoint);
      expect(cmp.picks['jardem'], ['u1']);
      expect(jsonDecode(seen.last.body), {'category': 'emergency', 'lat': 43.2445, 'lon': 76.9457});
    });
  });

  group('errors', () {
    Future<ApiException> failure(http.Response response) async {
      final (api, _) = _client((_) => response);
      try {
        await api.createIncident(category: 'emergency', at: kDemoPoint);
      } on ApiException catch (e) {
        return e;
      }
      fail('expected ApiException');
    }

    test('422 with a string detail (outside Almaty)', () async {
      final e = await failure(_ok({'detail': 'the location is outside the Almaty service area'}, 422));
      expect(e.status, 422);
      expect(e.detail, 'the location is outside the Almaty service area');
      expect(e.isUnprocessable, isTrue);
      expect(e.isRateLimited, isFalse);
      expect(e.isNetwork, isFalse);
      expect(e.toString(), 'ApiException(422, the location is outside the Almaty service area)');
    });

    test('422 with FastAPI validation list', () async {
      final e = await failure(
        _ok({
          'detail': [
            {
              'loc': ['body', 'lat'],
              'msg': 'Field required',
              'type': 'missing',
            },
            {
              'loc': ['body', 'lon'],
              'msg': 'Input should be a number',
              'type': 'float',
            },
          ],
        }, 422),
      );
      expect(e.detail, 'Field required; Input should be a number');
    });

    test('status helpers and Russian messages', () async {
      final cases = {
        401: (ApiException e) => e.isUnauthorized,
        403: (ApiException e) => e.isForbidden,
        404: (ApiException e) => e.isNotFound,
        409: (ApiException e) => e.isConflict,
        429: (ApiException e) => e.isRateLimited,
      };
      final messages = <String>{};
      for (final entry in cases.entries) {
        final e = await failure(_ok({'detail': 'x'}, entry.key));
        expect(e.status, entry.key);
        expect(entry.value(e), isTrue, reason: '${entry.key}');
        expect(e.userMessage, matches(RegExp('[А-Яа-я]')));
        messages.add(e.userMessage);
      }
      expect(messages, hasLength(cases.length), reason: 'each status has its own message');
      expect(const ApiException(401, '').userMessage, contains('Войдите'));
      expect(const ApiException(429, '').userMessage, contains('Слишком много'));
    });

    test('non-JSON error body is passed through', () async {
      final e = await failure(http.Response('Bad Gateway', 502));
      expect(e.status, 502);
      expect(e.detail, 'Bad Gateway');
      expect(e.userMessage, contains('502'));
    });

    test('JSON error without detail keeps the raw body', () async {
      final e = await failure(_ok({'error': 'boom'}, 500));
      expect(e.detail, '{"error":"boom"}');
    });

    test('boundaries of the success range', () async {
      expect((await failure(http.Response('', 199))).status, 199);
      expect((await failure(http.Response('', 300))).status, 300);
      final (api, _) = _client((_) => http.Response('', 204));
      await api.liftClosure('c1'); // 2xx with an empty body is fine
      final (api2, _) = _client((_) => _ok(fixture('incident'), 299));
      expect((await api2.incident('x')).id, 'inc-45831');
    });

    test('transport failures become status 0', () async {
      final (api, _) = _client((_) => throw http.ClientException('Connection refused'));
      await expectLater(
        api.meta(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 0)
              .having((e) => e.isNetwork, 'isNetwork', isTrue)
              .having((e) => e.detail, 'detail', 'Connection refused')
              .having((e) => e.userMessage, 'userMessage', contains('Нет соединения')),
        ),
      );
      final (api2, _) = _client((_) => throw StateError('socket gone'));
      await expectLater(api2.meta(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
    });

    test('timeout', () async {
      final api = ApiClient(
        baseUrl: _base,
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        api.meta(),
        throwsA(isA<ApiException>().having((e) => e.detail, 'detail', 'timeout').having((e) => e.status, 'status', 0)),
      );
    });

    test('a failed login does not set a token', () async {
      final (api, _) = _client((_) => _ok({'detail': 'invalid pin'}, 401));
      await expectLater(api.loginResponder(login: 'smp7', pin: '0000'), throwsA(isA<ApiException>()));
      expect(api.token, isNull);
    });

    test('malformed success body yields tolerant defaults', () async {
      final (api, _) = _client((_) => http.Response('<html>', 200));
      expect((await api.meta()).city, 'Алматы');
      expect(await api.catalog(), isEmpty);
    });
  });
}
