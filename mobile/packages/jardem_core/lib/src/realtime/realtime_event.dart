import '../models/enums.dart';
import '../models/json.dart';
import '../models/unit.dart';

/// Typed server → client notification from `/ws`.
sealed class RealtimeEvent {
  const RealtimeEvent();

  /// Parses one decoded message; null for `hello` and unknown types.
  static RealtimeEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = asJson(raw);
    switch (j['type']) {
      case 'units.moved':
        return UnitsMoved(listOf(j['units'], UnitPosition.fromJson));
      case 'unit.updated':
        final unit = asJson(j['unit']);
        final id = strOrNull(unit, 'id') ?? strOrNull(j, 'unit_id');
        if (id == null) return null;
        return UnitUpdated(
          unitId: id,
          unit: unit.isEmpty ? null : Unit.fromJson(unit),
          incidentId: strOrNull(j, 'incident_id'),
        );
      case 'incident.updated':
        final id = strOrNull(j, 'incident_id');
        if (id == null) return null;
        return IncidentUpdated(
          incidentId: id,
          status: j['status'] == null ? null : IncidentStatus.parse(j['status']),
          service: ServiceType.tryParse(j['service']),
          unitIds: strings(j['unit_ids']),
        );
      case 'message.created':
        return MessageCreated(str(j, 'unit_id'));
      case 'traffic.updated':
        return const TrafficUpdated();
      default:
        return null;
    }
  }
}

class UnitsMoved extends RealtimeEvent {
  const UnitsMoved(this.units);
  final List<UnitPosition> units;
}

class UnitUpdated extends RealtimeEvent {
  const UnitUpdated({required this.unitId, this.unit, this.incidentId});
  final String unitId;
  final Unit? unit;
  final String? incidentId;
}

class IncidentUpdated extends RealtimeEvent {
  const IncidentUpdated({required this.incidentId, this.status, this.service, this.unitIds = const []});
  final String incidentId;
  final IncidentStatus? status;
  final ServiceType? service;
  final List<String> unitIds;
}

class MessageCreated extends RealtimeEvent {
  const MessageCreated(this.unitId);
  final String unitId;
}

class TrafficUpdated extends RealtimeEvent {
  const TrafficUpdated();
}
