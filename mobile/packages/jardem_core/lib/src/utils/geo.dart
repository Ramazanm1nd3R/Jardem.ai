/// Geometry helpers. API line geometries are GeoJSON-ordered `[lon, lat]`.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const double kEarthRadiusM = 6371000;

/// Demo fallback location used when no real fix inside the city is available.
const LatLng kDemoPoint = LatLng(43.2445, 76.9457);
const String kDemoAddress = 'ул. Назарбаева, 125, Алматы';

/// Converts one `[lon, lat]` pair; null when malformed.
LatLng? lonLatToLatLng(Object? pair) {
  if (pair is! List || pair.length < 2) return null;
  final lon = pair[0], lat = pair[1];
  if (lon is! num || lat is! num) return null;
  return LatLng(lat.toDouble(), lon.toDouble());
}

/// Converts a list of `[lon, lat]` pairs, skipping malformed entries.
List<LatLng> lineFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final p in raw)
      if (lonLatToLatLng(p) case final LatLng point) point,
  ];
}

/// Great-circle distance in metres.
double haversineM(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * kEarthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

double _rad(double deg) => deg * math.pi / 180;

/// Length of a polyline in metres (0 for fewer than two points).
double polylineLengthM(List<LatLng> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += haversineM(points[i - 1], points[i]);
  }
  return total;
}

/// Axis-aligned bounding box in degrees.
class GeoBounds {
  const GeoBounds(this.minLat, this.minLon, this.maxLat, this.maxLon);

  final double minLat, minLon, maxLat, maxLon;

  /// Parses the API's `[minLat, minLon, maxLat, maxLon]`.
  static GeoBounds? fromList(Object? raw) {
    if (raw is! List || raw.length != 4 || raw.any((v) => v is! num)) return null;
    final v = raw.cast<num>().map((n) => n.toDouble()).toList();
    return GeoBounds(v[0], v[1], v[2], v[3]);
  }

  LatLng get southWest => LatLng(minLat, minLon);
  LatLng get northEast => LatLng(maxLat, maxLon);
  LatLng get center => LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);

  /// Inclusive containment test.
  bool contains(LatLng p) =>
      p.latitude >= minLat && p.latitude <= maxLat && p.longitude >= minLon && p.longitude <= maxLon;

  /// `minLat,minLon,maxLat,maxLon` as expected by `/traffic?bbox=`.
  String toQuery() => '$minLat,$minLon,$maxLat,$maxLon';

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.minLat == minLat &&
      other.minLon == minLon &&
      other.maxLat == maxLat &&
      other.maxLon == maxLon;

  @override
  int get hashCode => Object.hash(minLat, minLon, maxLat, maxLon);

  @override
  String toString() => 'GeoBounds(${toQuery()})';
}

/// Almaty service area used until `/meta.bbox` has been loaded.
const GeoBounds kAlmatyBounds = GeoBounds(43.118165, 76.738513, 43.397272, 77.07995);

/// Smallest box containing all [points]; null for an empty list.
GeoBounds? boundsOf(Iterable<LatLng> points) {
  GeoBounds? box;
  for (final p in points) {
    box = box == null
        ? GeoBounds(p.latitude, p.longitude, p.latitude, p.longitude)
        : GeoBounds(
            math.min(box.minLat, p.latitude),
            math.min(box.minLon, p.longitude),
            math.max(box.maxLat, p.latitude),
            math.max(box.maxLon, p.longitude),
          );
  }
  return box;
}

/// Whether [point] may be served: inside [area] (the city bbox from `/meta`).
bool inServiceArea(LatLng? point, [GeoBounds area = kAlmatyBounds]) => point != null && area.contains(point);

/// Linear interpolation between two positions, [t] clamped to 0…1.
LatLng lerpLatLng(LatLng a, LatLng b, double t) {
  final k = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  return LatLng(a.latitude + (b.latitude - a.latitude) * k, a.longitude + (b.longitude - a.longitude) * k);
}
