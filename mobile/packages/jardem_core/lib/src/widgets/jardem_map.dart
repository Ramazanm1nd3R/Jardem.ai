import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/enums.dart';
import '../models/route.dart';
import '../models/traffic.dart';
import '../models/unit.dart';
import '../theme/jardem_colors.dart';
import '../theme/jardem_theme.dart';
import '../utils/geo.dart';
import '../utils/traffic.dart';
import 'map_markers.dart';
import 'map_tiles.dart';

/// One unit on the map.
class MapUnit {
  const MapUnit({
    required this.id,
    required this.position,
    required this.service,
    this.highlighted = false,
    this.dimmed = false,
  });

  factory MapUnit.of(Unit u, {bool highlighted = false, bool dimBusy = false}) =>
      MapUnit(id: u.id, position: u.position, service: u.service, highlighted: highlighted, dimmed: dimBusy && !u.free);

  final String id;
  final LatLng position;
  final ServiceType service;
  final bool highlighted;
  final bool dimmed;
}

/// A route polyline. With [sections] it is drawn traffic-coloured (responder
/// navigation); otherwise in [color], optionally [dashed] (citizen screens).
class MapRoute {
  const MapRoute({
    required this.points,
    this.color = JardemColors.primary,
    this.dashed = false,
    this.sections = const [],
    this.width = 4,
  });

  /// Traffic-coloured variant from a `/route` result.
  factory MapRoute.traffic(RouteResult route, {double width = 6}) =>
      MapRoute(points: route.geometry, sections: route.sections, width: width);

  final List<LatLng> points;
  final Color color;
  final bool dashed;
  final List<RouteSection> sections;
  final double width;
}

/// CARTO Voyager map with Jardem layers: traffic, routes, units, my location.
///
/// Unit markers glide between successive positions, so feeding it realtime
/// `units.moved` updates produces smooth motion.
class JardemMap extends StatelessWidget {
  const JardemMap({
    super.key,
    this.controller,
    this.center = kDemoPoint,
    this.zoom = 13.5,
    this.fitPoints,
    this.fitPadding = const EdgeInsets.all(48),
    this.units = const [],
    this.myLocation,
    this.destination,
    this.destinationColor = JardemColors.danger,
    this.routes = const [],
    this.traffic,
    this.interactive = true,
    this.onTap,
    this.onLongPress,
    this.onUnitTap,
    this.onMapReady,
    this.attributionAlignment = Alignment.bottomLeft,
    this.attributionPadding = const EdgeInsets.all(6),
    this.moveDuration = const Duration(milliseconds: 1100),
  });

  /// Tile source for every map in the app (see [MapTiles] for overriding).
  static MapTiles tiles = MapTiles.fromEnvironment();

  /// Credit line that must stay visible on the map and in «О приложении».
  static String get attribution => tiles.attribution;

  // Mixes 45 % grey into each channel and lifts it towards a pale blue-white.
  static const ColorFilter _soften = ColorFilter.matrix(<double>[
    0.640, 0.300, 0.040, 0, 26, //
    0.105, 0.830, 0.045, 0, 28, //
    0.105, 0.300, 0.575, 0, 34, //
    0, 0, 0, 1, 0,
  ]);

  /// Set to false in widget tests to avoid network tile requests.
  static bool tilesEnabled = true;

  final MapController? controller;
  final LatLng center;
  final double zoom;

  /// When set (2+ distinct points) the initial camera frames these points.
  final List<LatLng>? fitPoints;
  final EdgeInsets fitPadding;
  final List<MapUnit> units;
  final LatLng? myLocation;
  final LatLng? destination;
  final Color destinationColor;
  final List<MapRoute> routes;

  /// Draws the traffic layer (segments, hotspots, closures) when non-null.
  final TrafficData? traffic;
  final bool interactive;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<LatLng>? onLongPress;
  final ValueChanged<String>? onUnitTap;
  final VoidCallback? onMapReady;
  final Alignment attributionAlignment;
  final EdgeInsets attributionPadding;

  /// How long a marker takes to glide to a new position.
  final Duration moveDuration;

  /// Camera framing [points] with [padding]; null when there is nothing to frame.
  static CameraFit? fitFor(List<LatLng>? points, EdgeInsets padding) {
    if (points == null || points.length < 2) return null;
    final box = boundsOf(points)!;
    if (box.southWest == box.northEast) return null;
    return CameraFit.bounds(bounds: LatLngBounds(box.southWest, box.northEast), padding: padding, maxZoom: 16);
  }

  @override
  Widget build(BuildContext context) {
    final t = traffic;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        initialCameraFit: fitFor(fitPoints, fitPadding),
        minZoom: 9,
        maxZoom: 18,
        backgroundColor: const Color(0xFFEAF1F8),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
        onTap: onTap == null ? null : (_, p) => onTap!(p),
        onLongPress: onLongPress == null ? null : (_, p) => onLongPress!(p),
        onMapReady: onMapReady,
      ),
      children: [
        if (tilesEnabled)
          TileLayer(
            urlTemplate: tiles.urlTemplate,
            subdomains: tiles.subdomains,
            // Only request @2x tiles when the source really has them.
            retinaMode: tiles.urlTemplate.contains('{r}') && RetinaMode.isHighDensity(context),
            userAgentPackageName: 'ai.jardem.app',
            maxNativeZoom: 19,
            tileBuilder: tiles.soften ? (context, tile, _) => ColorFiltered(colorFilter: _soften, child: tile) : null,
          ),
        if (t != null) ...[
          CircleLayer(
            circles: [
              for (final h in t.hotspots)
                CircleMarker(
                  point: h.position,
                  radius: h.radiusM,
                  useRadiusInMeter: true,
                  color: _hotspotColor(h).withValues(alpha: 0.10 + 0.12 * h.severity.clamp(0, 1)),
                  borderColor: _hotspotColor(h).withValues(alpha: 0.35),
                  borderStrokeWidth: 1,
                ),
            ],
          ),
          PolylineLayer(
            polylines: [
              for (final s in t.segments)
                if (s.points.length > 1 && s.level != TrafficLevel.free) _trafficLine(s.points, s.level, 3.5),
            ],
          ),
        ],
        PolylineLayer(polylines: [for (final r in routes) ..._routeLines(r)]),
        if (t != null)
          MarkerLayer(
            markers: [
              for (final h in t.hotspots)
                if (h.kind != 'jam')
                  Marker(
                    point: h.position,
                    width: 24,
                    height: 24,
                    child: TrafficBadge(
                      icon: h.kind == 'accident' ? Icons.car_crash_rounded : Icons.construction_rounded,
                      color: _hotspotColor(h),
                    ),
                  ),
              for (final c in t.closures)
                Marker(
                  point: c.position,
                  width: 26,
                  height: 26,
                  child: TrafficBadge(icon: Icons.block_rounded, color: TrafficLevel.closed.color, size: 26),
                ),
            ],
          ),
        if (myLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: myLocation!,
                width: 64,
                height: 64,
                child: const IgnorePointer(child: MyLocationDot()),
              ),
            ],
          ),
        if (destination != null)
          MarkerLayer(
            markers: [
              Marker(
                point: destination!,
                width: 36,
                height: 36,
                alignment: Alignment.topCenter,
                child: IgnorePointer(child: DestinationPin(color: destinationColor)),
              ),
            ],
          ),
        AnimatedUnitLayer(units: units, duration: moveDuration, onUnitTap: onUnitTap),
        Align(
          alignment: attributionAlignment,
          child: Padding(padding: attributionPadding, child: const MapAttribution()),
        ),
      ],
    );
  }

  static Color _hotspotColor(TrafficHotspot h) => switch (h.kind) {
    'accident' => TrafficLevel.heavy.color,
    'roadworks' => TrafficLevel.jam.color,
    _ => TrafficLevel.jam.color,
  };

  static Polyline _trafficLine(List<LatLng> points, TrafficLevel level, double width) => Polyline(
    points: points,
    color: level.color.withValues(alpha: 0.9),
    strokeWidth: width,
    strokeCap: StrokeCap.round,
    pattern: level.dashed ? StrokePattern.dashed(segments: const [6, 6]) : const StrokePattern.solid(),
  );

  static List<Polyline> _routeLines(MapRoute r) {
    if (r.sections.isNotEmpty) {
      return [
        if (r.points.length > 1)
          Polyline(points: r.points, color: Colors.white, strokeWidth: r.width + 4, strokeCap: StrokeCap.round),
        for (final s in r.sections)
          if (s.geometry.length > 1)
            Polyline(
              points: s.geometry,
              // Free-flowing stretches use the brand blue, as in the mock-up.
              color: s.level == TrafficLevel.free ? JardemColors.primary : s.level.color,
              strokeWidth: r.width,
              strokeCap: StrokeCap.round,
              pattern: s.level.dashed ? StrokePattern.dashed(segments: const [8, 8]) : const StrokePattern.solid(),
            ),
      ];
    }
    if (r.points.length < 2) return const [];
    return [
      Polyline(
        points: r.points,
        color: r.color,
        strokeWidth: r.width,
        strokeCap: StrokeCap.round,
        borderColor: r.dashed ? Colors.transparent : Colors.white,
        borderStrokeWidth: r.dashed ? 0 : 2,
        pattern: r.dashed ? StrokePattern.dashed(segments: const [7, 7]) : const StrokePattern.solid(),
      ),
    ];
  }
}

/// «© OpenStreetMap contributors, © CARTO» pill.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6)),
      child: Text(JardemMap.attribution, style: JardemTheme.text(9, FontWeight.w600, color: JardemColors.muted)),
    ),
  );
}

/// Marker layer whose markers animate from their previous to their new position.
class AnimatedUnitLayer extends StatefulWidget {
  const AnimatedUnitLayer({super.key, required this.units, required this.duration, this.onUnitTap});

  final List<MapUnit> units;
  final Duration duration;
  final ValueChanged<String>? onUnitTap;

  @override
  State<AnimatedUnitLayer> createState() => _AnimatedUnitLayerState();
}

class _AnimatedUnitLayerState extends State<AnimatedUnitLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: widget.duration, value: 1);
  Map<String, LatLng> _from = const {};

  LatLng _shown(MapUnit u, double t) {
    final from = _from[u.id];
    return from == null ? u.position : lerpLatLng(from, u.position, t);
  }

  @override
  void didUpdateWidget(AnimatedUnitLayer old) {
    super.didUpdateWidget(old);
    var changed = false;
    final current = <String, LatLng>{};
    final t = _anim.value;
    final next = {for (final u in widget.units) u.id: u.position};
    for (final u in old.units) {
      final target = next[u.id];
      if (target == null) continue;
      current[u.id] = _shown(u, t);
      if (target != u.position) changed = true;
    }
    if (changed) {
      _from = current;
      _anim
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, _) {
      final t = _anim.value;
      // Highlighted markers are painted last so they stay on top.
      final ordered = [...widget.units.where((u) => !u.highlighted), ...widget.units.where((u) => u.highlighted)];
      return MarkerLayer(markers: [for (final u in ordered) _marker(u, _shown(u, t))]);
    },
  );

  Marker _marker(MapUnit u, LatLng at) {
    final tap = widget.onUnitTap;
    Widget wrap(Widget child) => tap == null
        ? IgnorePointer(child: child)
        : GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => tap(u.id), child: child);
    if (u.highlighted) {
      final pin = HighlightedUnitPin(service: u.service);
      return Marker(key: ValueKey('unit-${u.id}'), point: at, width: pin.extent, height: pin.extent, child: wrap(pin));
    }
    const size = 34.0;
    return Marker(
      key: ValueKey('unit-${u.id}'),
      point: at,
      width: size,
      height: size * 1.18,
      alignment: Alignment.topCenter,
      child: wrap(UnitPin(service: u.service, size: size, dimmed: u.dimmed)),
    );
  }
}
