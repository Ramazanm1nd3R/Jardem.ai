import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/events.dart';

void main() {
  const me = 'ambulance-7-1';

  group('concernsCrew', () {
    test('unit.updated for this unit or this incident', () {
      expect(concernsCrew(const UnitUpdated(unitId: me), unitId: me), isTrue);
      expect(concernsCrew(const UnitUpdated(unitId: 'fire-1'), unitId: me), isFalse);
      expect(
        concernsCrew(
          const UnitUpdated(unitId: 'fire-1', incidentId: 'inc-1'),
          unitId: me,
          incidentId: 'inc-1',
        ),
        isTrue,
      );
      expect(
        concernsCrew(
          const UnitUpdated(unitId: 'fire-1', incidentId: 'inc-2'),
          unitId: me,
          incidentId: 'inc-1',
        ),
        isFalse,
      );
      // No current incident: a null incident id on the event must not match.
      expect(concernsCrew(const UnitUpdated(unitId: 'fire-1'), unitId: me), isFalse);
      expect(
        concernsCrew(
          const UnitUpdated(unitId: 'fire-1', incidentId: 'inc-1'),
          unitId: me,
        ),
        isFalse,
      );
    });

    test('incident.updated naming this unit or the current incident', () {
      expect(
        concernsCrew(
          const IncidentUpdated(incidentId: 'inc-9', unitIds: ['x', me]),
          unitId: me,
        ),
        isTrue,
      );
      expect(
        concernsCrew(
          const IncidentUpdated(incidentId: 'inc-9', unitIds: ['x']),
          unitId: me,
        ),
        isFalse,
      );
      expect(
        concernsCrew(
          const IncidentUpdated(incidentId: 'inc-1'),
          unitId: me,
          incidentId: 'inc-1',
        ),
        isTrue,
      );
      expect(
        concernsCrew(
          const IncidentUpdated(incidentId: 'inc-2'),
          unitId: me,
          incidentId: 'inc-1',
        ),
        isFalse,
      );
      expect(concernsCrew(const IncidentUpdated(incidentId: 'inc-2'), unitId: me), isFalse);
    });

    test('message.created for this unit only', () {
      expect(concernsCrew(const MessageCreated(me), unitId: me), isTrue);
      expect(concernsCrew(const MessageCreated('fire-1'), unitId: me), isFalse);
    });

    test('other events never trigger a refresh', () {
      expect(concernsCrew(const TrafficUpdated(), unitId: me, incidentId: 'inc-1'), isFalse);
      expect(
        concernsCrew(
          const UnitsMoved([UnitPosition(id: me, service: ServiceType.ambulance)]),
          unitId: me,
        ),
        isFalse,
      );
    });
  });

  test('ownPosition', () {
    const batch = UnitsMoved([
      UnitPosition(id: 'fire-1', service: ServiceType.fire, lat: 1, lon: 2),
      UnitPosition(id: me, service: ServiceType.ambulance, lat: 43.28, lon: 76.99),
    ]);
    expect(ownPosition(batch, me)!.lat, 43.28);
    expect(ownPosition(batch, 'fire-1')!.lon, 2);
    expect(ownPosition(batch, 'police-1'), isNull);
    expect(ownPosition(const UnitsMoved([]), me), isNull);
  });
}
