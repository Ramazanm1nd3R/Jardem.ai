/// Which realtime notifications concern this crew.
library;

import 'package:jardem_core/jardem_core.dart';

/// True when `/responder/me` should be re-fetched after [event].
bool concernsCrew(RealtimeEvent event, {required String unitId, String? incidentId}) => switch (event) {
  UnitUpdated(unitId: final id, incidentId: final inc) => id == unitId || (incidentId != null && inc == incidentId),
  IncidentUpdated(incidentId: final id, :final unitIds) =>
    unitIds.contains(unitId) || (incidentId != null && id == incidentId),
  MessageCreated(unitId: final id) => id == unitId,
  _ => false,
};

/// This crew's entry in a `units.moved` batch, if it moved.
UnitPosition? ownPosition(UnitsMoved event, String unitId) {
  for (final p in event.units) {
    if (p.id == unitId) return p;
  }
  return null;
}
