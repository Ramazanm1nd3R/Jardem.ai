import 'incident.dart';
import 'json.dart';
import 'unit.dart';

class ResponderCounters {
  const ResponderCounters({this.active = 0, this.enRoute = 0, this.onScene = 0});

  factory ResponderCounters.fromJson(Json j) =>
      ResponderCounters(active: integer(j, 'active'), enRoute: integer(j, 'en_route'), onScene: integer(j, 'on_scene'));

  final int active;
  final int enRoute;
  final int onScene;
}

/// `GET /responder/me`.
class ResponderState {
  const ResponderState({
    required this.unit,
    this.assignment,
    this.counters = const ResponderCounters(),
    this.unread = 0,
  });

  factory ResponderState.fromJson(Json j) => ResponderState(
    unit: Unit.fromJson(asJson(j['unit'])),
    assignment: j['assignment'] is Map ? Incident.fromJson(asJson(j['assignment'])) : null,
    counters: ResponderCounters.fromJson(asJson(j['counters'])),
    unread: integer(j, 'unread'),
  );

  final Unit unit;

  /// Current incident with the `my` leg (route, maneuvers), if any.
  final Incident? assignment;
  final ResponderCounters counters;
  final int unread;
}

/// Chat message between a crew and dispatch.
class Message {
  const Message({required this.id, this.unitId = '', this.sender = '', this.author = '', this.text = '', this.at});

  factory Message.fromJson(Json j) => Message(
    id: str(j, 'id'),
    unitId: str(j, 'unit_id'),
    sender: str(j, 'sender'),
    author: str(j, 'author'),
    text: str(j, 'text'),
    at: dateOrNull(j, 'at'),
  );

  static List<Message> listFromJson(Object? raw) => listOf(raw, Message.fromJson);

  final String id;
  final String unitId;

  /// `unit` or `dispatcher`.
  final String sender;
  final String author;
  final String text;
  final DateTime? at;

  bool get fromDispatcher => sender == 'dispatcher';
}
