import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'enums.dart';
import 'json.dart';

/// A station / precinct / fire house.
class Department {
  const Department({
    required this.id,
    required this.service,
    required this.name,
    this.address = '',
    this.lat = 0,
    this.lon = 0,
    this.approximate = false,
    this.distanceM,
    this.units = 0,
    this.unitsFree = 0,
  });

  factory Department.fromJson(Json j) => Department(
    id: str(j, 'id'),
    service: ServiceType.parse(j['service']),
    name: str(j, 'name'),
    address: str(j, 'address'),
    lat: dbl(j, 'lat'),
    lon: dbl(j, 'lon'),
    approximate: boolean(j, 'approximate'),
    distanceM: intOrNull(j, 'distance_m'),
    units: integer(j, 'units'),
    unitsFree: integer(j, 'units_free'),
  );

  final String id;
  final ServiceType service;
  final String name;
  final String address;
  final double lat;
  final double lon;
  final bool approximate;
  final int? distanceM;
  final int units;
  final int unitsFree;

  LatLng get position => LatLng(lat, lon);
}

class CrewMember {
  const CrewMember({
    required this.id,
    required this.name,
    this.role = '',
    this.phone = '',
    this.lead = false,
    this.online = false,
  });

  factory CrewMember.fromJson(Json j) => CrewMember(
    id: str(j, 'id'),
    name: str(j, 'name'),
    role: str(j, 'role'),
    phone: str(j, 'phone'),
    lead: boolean(j, 'lead'),
    online: boolean(j, 'online'),
  );

  final String id;
  final String name;
  final String role;
  final String phone;
  final bool lead;
  final bool online;
}

class EquipmentItem {
  const EquipmentItem({required this.name, this.detail = '', this.ok = true});

  factory EquipmentItem.fromJson(Json j) =>
      EquipmentItem(name: str(j, 'name'), detail: str(j, 'detail'), ok: boolean(j, 'ok', true));

  final String name;
  final String detail;
  final bool ok;
}

/// A crew / vehicle. Public listings fill the first block of fields; the
/// responder's own unit additionally carries crew, equipment and shift data.
class Unit {
  const Unit({
    required this.id,
    required this.service,
    this.kind = '',
    this.status = UnitStatus.unknown,
    this.lat = 0,
    this.lon = 0,
    this.heading = 0,
    this.name = '',
    this.callsign = '',
    this.departmentId = '',
    this.departmentName = '',
    this.department,
    this.statusLabel = '',
    this.free = false,
    this.plate = '',
    this.vehicle = '',
    this.photo = '',
    this.capabilities = const [],
    this.distanceM,
    this.etaS,
    this.route = const [],
    this.lead,
    this.fuelPct,
    this.crew = const [],
    this.equipment = const [],
    this.shiftStartedAt,
    this.incidentId,
  });

  factory Unit.fromJson(Json j) {
    final status = UnitStatus.parse(j['status']);
    // `department` is an object on /units/{id} but a plain name on /responder/me.
    final rawDept = j['department'];
    final department = rawDept is Map ? Department.fromJson(asJson(rawDept)) : null;
    return Unit(
      id: str(j, 'id'),
      service: ServiceType.parse(j['service']),
      kind: str(j, 'kind'),
      status: status,
      lat: dbl(j, 'lat'),
      lon: dbl(j, 'lon'),
      heading: dbl(j, 'heading'),
      name: str(j, 'name'),
      callsign: str(j, 'callsign'),
      departmentId: str(j, 'department_id'),
      departmentName: rawDept is String ? rawDept : (department?.name ?? ''),
      department: department,
      statusLabel: str(j, 'status_label', status.label),
      free: boolean(j, 'free', status.isFree),
      plate: str(j, 'plate'),
      vehicle: str(j, 'vehicle'),
      photo: str(j, 'photo'),
      capabilities: strings(j['capabilities']),
      distanceM: intOrNull(j, 'distance_m'),
      etaS: intOrNull(j, 'eta_s'),
      route: lineFromJson(j['route']),
      lead: strOrNull(j, 'lead'),
      fuelPct: intOrNull(j, 'fuel_pct'),
      crew: listOf(j['crew'], CrewMember.fromJson),
      equipment: listOf(j['equipment'], EquipmentItem.fromJson),
      shiftStartedAt: dateOrNull(j, 'shift_started_at'),
      incidentId: strOrNull(j, 'incident_id'),
    );
  }

  static List<Unit> listFromJson(Object? raw) => listOf(raw, Unit.fromJson);

  final String id;
  final ServiceType service;
  final String kind;
  final UnitStatus status;
  final double lat;
  final double lon;
  final double heading;
  final String name;
  final String callsign;
  final String departmentId;
  final String departmentName;
  final Department? department;
  final String statusLabel;
  final bool free;
  final String plate;
  final String vehicle;

  /// Basename of the bundled photo, e.g. `ambulance_kz_1`.
  final String photo;
  final List<String> capabilities;
  final int? distanceM;
  final int? etaS;

  /// Remaining route to the requested point / incident, if the API sent one.
  final List<LatLng> route;
  final String? lead;
  final int? fuelPct;
  final List<CrewMember> crew;
  final List<EquipmentItem> equipment;
  final DateTime? shiftStartedAt;
  final String? incidentId;

  LatLng get position => LatLng(lat, lon);
  bool get onDuty => status != UnitStatus.offDuty;

  /// Applies a realtime position update.
  Unit moved(UnitPosition p) => copyWith(
    lat: p.lat,
    lon: p.lon,
    heading: p.heading,
    status: p.status,
    statusLabel: p.status.label,
    free: p.status.isFree,
  );

  Unit copyWith({
    double? lat,
    double? lon,
    double? heading,
    UnitStatus? status,
    String? statusLabel,
    bool? free,
    int? distanceM,
    int? etaS,
    List<LatLng>? route,
  }) => Unit(
    id: id,
    service: service,
    kind: kind,
    status: status ?? this.status,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    heading: heading ?? this.heading,
    name: name,
    callsign: callsign,
    departmentId: departmentId,
    departmentName: departmentName,
    department: department,
    statusLabel: statusLabel ?? this.statusLabel,
    free: free ?? this.free,
    plate: plate,
    vehicle: vehicle,
    photo: photo,
    capabilities: capabilities,
    distanceM: distanceM ?? this.distanceM,
    etaS: etaS ?? this.etaS,
    route: route ?? this.route,
    lead: lead,
    fuelPct: fuelPct,
    crew: crew,
    equipment: equipment,
    shiftStartedAt: shiftStartedAt,
    incidentId: incidentId,
  );
}

/// Compact unit record from the `units.moved` realtime event.
class UnitPosition {
  const UnitPosition({
    required this.id,
    required this.service,
    this.kind = '',
    this.status = UnitStatus.unknown,
    this.lat = 0,
    this.lon = 0,
    this.heading = 0,
  });

  factory UnitPosition.fromJson(Json j) => UnitPosition(
    id: str(j, 'id'),
    service: ServiceType.parse(j['service']),
    kind: str(j, 'kind'),
    status: UnitStatus.parse(j['status']),
    lat: dbl(j, 'lat'),
    lon: dbl(j, 'lon'),
    heading: dbl(j, 'heading'),
  );

  final String id;
  final ServiceType service;
  final String kind;
  final UnitStatus status;
  final double lat;
  final double lon;
  final double heading;

  LatLng get position => LatLng(lat, lon);
}
