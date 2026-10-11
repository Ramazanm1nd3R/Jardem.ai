import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import '../utils/traffic.dart';
import 'json.dart';

class TrafficSegment {
  const TrafficSegment({required this.level, this.speedKph, this.name = '', this.points = const []});

  /// Parses one GeoJSON `Feature` with a `LineString` geometry.
  factory TrafficSegment.fromFeature(Json j) {
    final props = asJson(j['properties']);
    return TrafficSegment(
      level: TrafficLevel.parse(props['level']),
      speedKph: dblOrNull(props, 'speed_kph'),
      name: str(props, 'name'),
      points: lineFromJson(asJson(j['geometry'])['coordinates']),
    );
  }

  final TrafficLevel level;
  final double? speedKph;
  final String name;
  final List<LatLng> points;
}

class TrafficHotspot {
  const TrafficHotspot({
    required this.id,
    required this.lat,
    required this.lon,
    this.radiusM = 0,
    this.severity = 0,
    this.kind = 'jam',
  });

  factory TrafficHotspot.fromJson(Json j) => TrafficHotspot(
    id: str(j, 'id'),
    lat: dbl(j, 'lat'),
    lon: dbl(j, 'lon'),
    radiusM: dbl(j, 'radius_m'),
    severity: dbl(j, 'severity'),
    kind: str(j, 'kind', 'jam'),
  );

  final String id;
  final double lat;
  final double lon;
  final double radiusM;
  final double severity;

  /// jam / accident / roadworks.
  final String kind;

  LatLng get position => LatLng(lat, lon);

  String get label => switch (kind) {
    'accident' => 'ДТП',
    'roadworks' => 'Дорожные работы',
    _ => 'Затор',
  };
}

class RoadClosure {
  const RoadClosure({required this.id, required this.lat, required this.lon, this.reason = ''});

  factory RoadClosure.fromJson(Json j) =>
      RoadClosure(id: str(j, 'id'), lat: dbl(j, 'lat'), lon: dbl(j, 'lon'), reason: str(j, 'reason'));

  final String id;
  final double lat;
  final double lon;
  final String reason;

  LatLng get position => LatLng(lat, lon);
}

class TrafficData {
  const TrafficData({
    this.simulated = true,
    this.index = 0,
    this.localHour,
    this.hotspots = const [],
    this.closures = const [],
    this.segments = const [],
  });

  factory TrafficData.fromJson(Json j) => TrafficData(
    simulated: boolean(j, 'simulated', true),
    index: integer(j, 'index'),
    localHour: dblOrNull(j, 'local_hour'),
    hotspots: listOf(j['hotspots'], TrafficHotspot.fromJson),
    closures: listOf(j['closures'], RoadClosure.fromJson),
    segments: listOf(asJson(j['segments'])['features'], TrafficSegment.fromFeature),
  );

  final bool simulated;

  /// City-wide congestion index, 0–10.
  final int index;
  final double? localHour;
  final List<TrafficHotspot> hotspots;
  final List<RoadClosure> closures;
  final List<TrafficSegment> segments;

  /// Segments grouped by level, e.g. for per-level styling.
  Map<TrafficLevel, List<TrafficSegment>> get byLevel {
    final out = <TrafficLevel, List<TrafficSegment>>{};
    for (final s in segments) {
      (out[s.level] ??= []).add(s);
    }
    return out;
  }
}
