import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import '../utils/traffic.dart';
import 'json.dart';

class RouteSection {
  const RouteSection({required this.level, this.geometry = const []});

  factory RouteSection.fromJson(Json j) =>
      RouteSection(level: TrafficLevel.parse(j['level']), geometry: lineFromJson(j['geometry']));

  final TrafficLevel level;
  final List<LatLng> geometry;
}

class Maneuver {
  const Maneuver({required this.kind, this.text = '', this.street = '', this.atM, this.inM, this.lat, this.lon});

  factory Maneuver.fromJson(Json j) => Maneuver(
    kind: str(j, 'kind'),
    text: str(j, 'text'),
    street: str(j, 'street'),
    atM: intOrNull(j, 'at_m'),
    inM: intOrNull(j, 'in_m'),
    lat: dblOrNull(j, 'lat'),
    lon: dblOrNull(j, 'lon'),
  );

  /// depart / left / right / slight_left / slight_right / uturn / arrive.
  final String kind;
  final String text;
  final String street;

  /// Offset from the route start (`/route`).
  final int? atM;

  /// Distance from the unit's current position (`/responder/me`).
  final int? inM;
  final double? lat;
  final double? lon;
}

class RouteResult {
  const RouteResult({
    this.distanceM = 0,
    this.durationS = 0,
    this.freeFlowS = 0,
    this.profile = '',
    this.geometry = const [],
    this.sections = const [],
    this.maneuvers = const [],
  });

  factory RouteResult.fromJson(Json j) => RouteResult(
    distanceM: integer(j, 'distance_m'),
    durationS: integer(j, 'duration_s'),
    freeFlowS: integer(j, 'free_flow_s'),
    profile: str(j, 'profile'),
    geometry: lineFromJson(j['geometry']),
    sections: listOf(j['sections'], RouteSection.fromJson),
    maneuvers: listOf(j['maneuvers'], Maneuver.fromJson),
  );

  final int distanceM;
  final int durationS;
  final int freeFlowS;
  final String profile;
  final List<LatLng> geometry;
  final List<RouteSection> sections;
  final List<Maneuver> maneuvers;
}
