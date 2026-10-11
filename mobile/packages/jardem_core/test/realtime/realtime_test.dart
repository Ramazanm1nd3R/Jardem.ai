import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// In-memory WebSocket: the test plays the server side.
class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _FakeChannel({this.failReady = false});

  final bool failReady;
  final incoming = StreamController<dynamic>();
  final _outgoing = StreamController<dynamic>();
  bool closed = false;

  @override
  Future<void> get ready => failReady ? Future.error(StateError('refused')) : Future.value();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _Sink(this, _outgoing.sink);

  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;

  void serverSend(Object json) => incoming.add(jsonEncode(json));
  Future<void> serverClose() => incoming.close();
}

class _Sink implements WebSocketSink {
  _Sink(this._channel, this._inner);
  final _FakeChannel _channel;
  final StreamSink<dynamic> _inner;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closed = true;
  }

  @override
  void add(dynamic event) => _inner.add(event);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<dynamic> stream) => _inner.addStream(stream);
  @override
  Future<void> get done => _inner.done;
}

void main() {
  group('RealtimeEvent.fromJson', () {
    test('units.moved', () {
      final e = RealtimeEvent.fromJson({
        'type': 'units.moved',
        'units': [
          {
            'id': 'fire-9-1',
            'service': 'fire',
            'kind': 'engine',
            'status': 'en_route',
            'lat': 43.25,
            'lon': 76.95,
            'heading': 90,
          },
          {'id': 'police-1-1', 'service': 'police', 'status': 'available', 'lat': 43.2, 'lon': 76.9},
        ],
      });
      expect(e, isA<UnitsMoved>());
      final units = (e as UnitsMoved).units;
      expect(units, hasLength(2));
      expect(units.first.id, 'fire-9-1');
      expect(units.first.service, ServiceType.fire);
      expect(units.first.kind, 'engine');
      expect(units.first.status, UnitStatus.enRoute);
      expect(units.first.position.latitude, 43.25);
      expect(units.first.position.longitude, 76.95);
      expect(units.first.heading, 90);
      expect(units.last.heading, 0);
    });

    test('unit.updated with a full unit', () {
      final e =
          RealtimeEvent.fromJson({
                'type': 'unit.updated',
                'unit': {'id': 'ambulance-1-2', 'service': 'ambulance', 'status': 'assigned'},
                'incident_id': 'inc-1',
              })
              as UnitUpdated;
      expect(e.unitId, 'ambulance-1-2');
      expect(e.unit!.status, UnitStatus.assigned);
      expect(e.incidentId, 'inc-1');
    });

    test('unit.updated with only an id', () {
      final e = RealtimeEvent.fromJson({'type': 'unit.updated', 'unit_id': 'u7'}) as UnitUpdated;
      expect(e.unitId, 'u7');
      expect(e.unit, isNull);
      expect(e.incidentId, isNull);
      expect(RealtimeEvent.fromJson({'type': 'unit.updated'}), isNull);
    });

    test('incident.updated', () {
      final e =
          RealtimeEvent.fromJson({
                'type': 'incident.updated',
                'incident_id': 'inc-45831',
                'status': 'en_route',
                'service': 'ambulance',
                'unit_ids': ['ambulance-1-2'],
              })
              as IncidentUpdated;
      expect(e.incidentId, 'inc-45831');
      expect(e.status, IncidentStatus.enRoute);
      expect(e.service, ServiceType.ambulance);
      expect(e.unitIds, ['ambulance-1-2']);

      final bare = RealtimeEvent.fromJson({'type': 'incident.updated', 'incident_id': 'i'}) as IncidentUpdated;
      expect(bare.status, isNull);
      expect(bare.service, isNull);
      expect(bare.unitIds, isEmpty);
      expect(RealtimeEvent.fromJson({'type': 'incident.updated'}), isNull);
    });

    test('message.created and traffic.updated', () {
      expect((RealtimeEvent.fromJson({'type': 'message.created', 'unit_id': 'u1'}) as MessageCreated).unitId, 'u1');
      expect(RealtimeEvent.fromJson({'type': 'traffic.updated'}), isA<TrafficUpdated>());
    });

    test('hello, unknown types and junk are ignored', () {
      expect(RealtimeEvent.fromJson({'type': 'hello'}), isNull);
      expect(RealtimeEvent.fromJson({'type': 'dispatch.proposed'}), isNull);
      expect(RealtimeEvent.fromJson({}), isNull);
      expect(RealtimeEvent.fromJson('hello'), isNull);
      expect(RealtimeEvent.fromJson(null), isNull);
      expect(RealtimeEvent.fromJson([1, 2]), isNull);
    });
  });

  group('RealtimeClient', () {
    test('delivers typed events and skips noise', () async {
      final channel = _FakeChannel();
      Uri? connectedTo;
      final client = RealtimeClient(
        'ws://api.test/api/v1/ws',
        channelFactory: (uri) {
          connectedTo = uri;
          return channel;
        },
      );
      final events = <RealtimeEvent>[];
      client.events.listen(events.add);
      client.connect();
      await pumpEventQueue();
      expect(connectedTo.toString(), 'ws://api.test/api/v1/ws');
      expect(client.isConnected, isTrue);

      channel.serverSend({'type': 'hello'});
      channel.incoming.add('not json');
      channel.incoming.add([1, 2, 3]); // binary frame
      channel.serverSend({'type': 'traffic.updated'});
      channel.serverSend({'type': 'incident.updated', 'incident_id': 'inc-1', 'status': 'on_scene'});
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events[0], isA<TrafficUpdated>());
      expect((events[1] as IncidentUpdated).status, IncidentStatus.onScene);
      await client.dispose();
      expect(channel.closed, isTrue);
    });

    test('events is a broadcast stream', () async {
      final client = RealtimeClient('ws://x/ws', channelFactory: (_) => _FakeChannel());
      expect(client.events.isBroadcast, isTrue);
      expect(client.connection.isBroadcast, isTrue);
      await client.dispose();
    });

    test('reconnects with growing backoff, then resets after success', () async {
      final channels = <_FakeChannel>[];
      final attempts = <int>[];
      var failing = true;
      final client = RealtimeClient(
        'ws://api.test/ws',
        channelFactory: (_) {
          final c = _FakeChannel(failReady: failing);
          channels.add(c);
          return c;
        },
        backoff: (attempt) {
          attempts.add(attempt);
          return const Duration(milliseconds: 5);
        },
      );
      final states = <bool>[];
      client.connection.listen(states.add);
      client.connect();
      client.connect(); // idempotent
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(channels.length, greaterThanOrEqualTo(3));
      expect(attempts.take(3), [0, 1, 2]);
      expect(client.isConnected, isFalse);

      failing = false;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.isConnected, isTrue);
      expect(states.last, isTrue);
      final connectedCount = channels.length;

      // Server drops the connection: the client reconnects from attempt 0.
      attempts.clear();
      await channels.last.serverClose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts.first, 0);
      expect(channels.length, connectedCount + 1);
      expect(client.isConnected, isTrue);
      expect(states, containsAllInOrder([true, false, true]));
      await client.dispose();
    });

    test('a throwing factory is retried', () async {
      var calls = 0;
      final client = RealtimeClient(
        'ws://api.test/ws',
        channelFactory: (_) {
          calls++;
          if (calls < 3) throw StateError('no network');
          return _FakeChannel();
        },
        backoff: (_) => const Duration(milliseconds: 2),
      );
      client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 3);
      expect(client.isConnected, isTrue);
      await client.dispose();
    });

    test('disconnect stops reconnecting; connect resumes', () async {
      final channels = <_FakeChannel>[];
      final client = RealtimeClient(
        'ws://api.test/ws',
        channelFactory: (_) {
          channels.add(_FakeChannel());
          return channels.last;
        },
        backoff: (_) => const Duration(milliseconds: 2),
      );
      client.connect();
      await pumpEventQueue();
      await client.disconnect();
      expect(client.isConnected, isFalse);
      expect(channels.single.closed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(channels, hasLength(1));

      client.connect();
      await pumpEventQueue();
      expect(channels, hasLength(2));
      expect(client.isConnected, isTrue);
      await client.dispose();
    });

    test('default schedule is reconnectDelay', () {
      expect(reconnectDelay(0), const Duration(seconds: 1));
    });
  });
}
