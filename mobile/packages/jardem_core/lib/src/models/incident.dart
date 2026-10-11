import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'enums.dart';
import 'json.dart';
import 'route.dart';
import 'triage.dart';
import 'unit.dart';

class TimelineEntry {
  const TimelineEntry({required this.status, this.at});

  factory TimelineEntry.fromJson(Json j) => TimelineEntry(status: str(j, 'status'), at: dateOrNull(j, 'at'));

  /// Raw status id; may be an incident status or a unit status (`transporting`).
  final String status;
  final DateTime? at;
}

/// The responder's own leg of an assignment (`assignment.my`).
class MyAssignment {
  const MyAssignment({this.etaS, this.distanceM, this.route = const [], this.maneuvers = const []});

  factory MyAssignment.fromJson(Json j) => MyAssignment(
    etaS: intOrNull(j, 'eta_s'),
    distanceM: intOrNull(j, 'distance_m'),
    route: lineFromJson(j['route']),
    maneuvers: listOf(j['maneuvers'], Maneuver.fromJson),
  );

  final int? etaS;
  final int? distanceM;
  final List<LatLng> route;
  final List<Maneuver> maneuvers;
}

class Incident {
  const Incident({
    required this.id,
    this.number = 0,
    required this.service,
    this.category = '',
    this.categoryTitle = '',
    this.serviceTitle = '',
    this.priority = 3,
    this.status = IncidentStatus.unknown,
    this.lat = 0,
    this.lon = 0,
    this.address = '',
    this.createdAt,
    this.closedAt,
    this.timeline = const [],
    this.units = const [],
    this.unitsRequired = 1,
    this.etaS,
    this.firstArrivalS,
    this.description = '',
    this.callerName = '',
    this.callerPhone = '',
    this.extraInfo = '',
    this.triage,
    this.my,
  });

  factory Incident.fromJson(Json j) {
    final service = ServiceType.parse(j['service']);
    return Incident(
      id: str(j, 'id'),
      number: integer(j, 'number'),
      service: service,
      category: str(j, 'category'),
      categoryTitle: str(j, 'category_title'),
      serviceTitle: str(j, 'service_title', service.title),
      priority: integer(j, 'priority', 3),
      status: IncidentStatus.parse(j['status']),
      lat: dbl(j, 'lat'),
      lon: dbl(j, 'lon'),
      address: str(j, 'address'),
      createdAt: dateOrNull(j, 'created_at'),
      closedAt: dateOrNull(j, 'closed_at'),
      timeline: listOf(j['timeline'], TimelineEntry.fromJson),
      units: Unit.listFromJson(j['units']),
      unitsRequired: integer(j, 'units_required', 1),
      etaS: intOrNull(j, 'eta_s'),
      firstArrivalS: intOrNull(j, 'first_arrival_s'),
      description: str(j, 'description'),
      callerName: str(j, 'caller_name'),
      callerPhone: str(j, 'caller_phone'),
      extraInfo: str(j, 'extra_info'),
      triage: j['triage'] is Map ? TriageResult.fromJson(asJson(j['triage'])) : null,
      my: j['my'] is Map ? MyAssignment.fromJson(asJson(j['my'])) : null,
    );
  }

  static List<Incident> listFromJson(Object? raw) => listOf(raw, Incident.fromJson);

  final String id;
  final int number;
  final ServiceType service;
  final String category;
  final String categoryTitle;
  final String serviceTitle;
  final int priority;
  final IncidentStatus status;
  final double lat;
  final double lon;
  final String address;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final List<TimelineEntry> timeline;
  final List<Unit> units;
  final int unitsRequired;
  final int? etaS;
  final int? firstArrivalS;
  final String description;
  final String callerName;
  final String callerPhone;
  final String extraInfo;
  final TriageResult? triage;
  final MyAssignment? my;

  LatLng get position => LatLng(lat, lon);

  /// The crew shown to the citizen: the one that will arrive first.
  Unit? get primaryUnit {
    Unit? best;
    for (final u in units) {
      if (best == null || (u.etaS ?? 1 << 30) < (best.etaS ?? 1 << 30)) best = u;
    }
    return best;
  }

  /// When the incident first reached [status], from the timeline.
  DateTime? reachedAt(IncidentStatus status) {
    for (final t in timeline) {
      if (t.status == status.id) return t.at;
    }
    return null;
  }
}

/// `GET /incidents` for a citizen.
class IncidentList {
  const IncidentList({this.active = const [], this.history = const []});

  factory IncidentList.fromJson(Json j) =>
      IncidentList(active: Incident.listFromJson(j['active']), history: Incident.listFromJson(j['history']));

  final List<Incident> active;
  final List<Incident> history;
}
