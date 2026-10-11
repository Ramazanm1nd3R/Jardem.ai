import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import 'crew.dart';
import 'providers.dart';

/// Whether the traffic layer is drawn on the navigation map.
final trafficLayerProvider = StateProvider<bool>((ref) => true);

/// City traffic snapshot, refreshed on `traffic.updated` and every minute.
final trafficProvider = FutureProvider.autoDispose<TrafficData>((ref) async {
  final sub = ref.watch(realtimeEventsProvider).where((e) => e is TrafficUpdated).listen((_) => ref.invalidateSelf());
  final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(() {
    sub.cancel();
    timer.cancel();
  });
  return ref.watch(apiClientProvider).traffic();
});

/// Other on-duty units of one service: REST snapshot + realtime positions.
class PeersController extends StateNotifier<List<Unit>> {
  PeersController(this._api, Stream<RealtimeEvent> events, this.service) : super(const []) {
    _sub = events.listen(_onEvent);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    refresh();
  }

  final ApiClient _api;
  final ServiceType service;
  late final StreamSubscription<RealtimeEvent> _sub;
  late final Timer _timer;

  Future<void> refresh() async {
    try {
      final units = await _api.units(service: service);
      if (mounted) state = units;
    } catch (_) {
      // The map simply keeps the last known peers.
    }
  }

  void _onEvent(RealtimeEvent event) {
    if (event is! UnitsMoved || state.isEmpty) return;
    final byId = {for (final p in event.units) p.id: p};
    if (!state.any((u) => byId.containsKey(u.id))) return;
    state = [
      for (final u in state)
        if (byId[u.id] case final UnitPosition p) u.moved(p) else u,
    ];
  }

  @override
  void dispose() {
    _sub.cancel();
    _timer.cancel();
    super.dispose();
  }
}

final peersProvider = StateNotifierProvider.autoDispose.family<PeersController, List<Unit>, ServiceType>(
  (ref, service) => PeersController(ref.watch(apiClientProvider), ref.watch(realtimeEventsProvider), service),
);

/// Traffic-coloured route from the unit's current position to the incident.
///
/// Re-requested every 10 s and on `traffic.updated`, so a new jam or closure
/// re-colours / re-routes the line. Null until the first answer (the screen
/// then falls back to `assignment.my.route`).
class NavRouteController extends StateNotifier<RouteResult?> {
  NavRouteController(this._api, Stream<RealtimeEvent> events, this._ref, {Duration every = const Duration(seconds: 10)})
    : super(null) {
    _sub = events.where((e) => e is TrafficUpdated).listen((_) => refresh());
    _timer = Timer.periodic(every, (_) => refresh());
    refresh();
  }

  final ApiClient _api;
  final Ref _ref;
  late final StreamSubscription<RealtimeEvent> _sub;
  late final Timer _timer;
  bool _busy = false;

  Future<void> refresh() async {
    final crew = _ref.read(crewProvider);
    final unit = crew.unit;
    final incident = crew.assignment;
    final heading = crew.status == UnitStatus.assigned || crew.status == UnitStatus.enRoute;
    if (unit == null || incident == null || !heading) {
      if (mounted && state != null) state = null;
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final route = await _api.route(unit.position, incident.position);
      if (mounted) state = route.geometry.length > 1 ? route : null;
    } catch (_) {
      // Keep the previous line; the fallback is `my.route`.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _timer.cancel();
    super.dispose();
  }
}

/// Keyed by incident id so a new call starts with a clean route.
final navRouteProvider = StateNotifierProvider.autoDispose.family<NavRouteController, RouteResult?, String>(
  (ref, incidentId) => NavRouteController(ref.watch(apiClientProvider), ref.watch(realtimeEventsProvider), ref),
);

/// Finished calls of this crew, reloaded when an incident changes.
final historyProvider = FutureProvider.autoDispose<List<Incident>>((ref) async {
  Timer? debounce;
  final sub = ref.watch(realtimeEventsProvider).where((e) => e is IncidentUpdated).listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 1), ref.invalidateSelf);
  });
  ref.onDispose(() {
    sub.cancel();
    debounce?.cancel();
  });
  return ref.watch(apiClientProvider).responderHistory();
});
