import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import 'providers.dart';

/// Parameters of a `/units` listing.
class UnitsQuery {
  const UnitsQuery({this.service, this.category, this.near, this.limit});

  final ServiceType? service;
  final String? category;
  final LatLng? near;
  final int? limit;

  @override
  bool operator ==(Object other) =>
      other is UnitsQuery &&
      other.service == service &&
      other.category == category &&
      other.near == near &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(service, category, near, limit);
}

/// A live unit list: REST snapshot + realtime position patches.
class UnitsController extends StateNotifier<AsyncValue<List<Unit>>> {
  UnitsController(
    this._api,
    Stream<RealtimeEvent> events,
    this.query, {
    Duration refreshEvery = const Duration(seconds: 20),
  }) : super(const AsyncValue.loading()) {
    _sub = events.listen(_onEvent);
    _timer = Timer.periodic(refreshEvery, (_) => refresh(silent: true));
    refresh();
  }

  final ApiClient _api;
  final UnitsQuery query;
  late final StreamSubscription<RealtimeEvent> _sub;
  late final Timer _timer;
  Timer? _debounce;

  Future<void> refresh({bool silent = false}) async {
    if (!silent && !state.hasValue) state = const AsyncValue.loading();
    try {
      final units = await _api.units(
        service: query.service,
        category: query.category,
        near: query.near,
        limit: query.limit,
      );
      if (mounted) state = AsyncValue.data(units);
    } catch (e, st) {
      // Keep showing the last good list on background refresh failures.
      if (mounted && !(silent && state.hasValue)) state = AsyncValue.error(e, st);
    }
  }

  void _onEvent(RealtimeEvent event) {
    switch (event) {
      case UnitsMoved(:final units):
        final current = state.valueOrNull;
        if (current == null) return;
        final byId = {for (final p in units) p.id: p};
        if (!current.any((u) => byId.containsKey(u.id))) return;
        state = AsyncValue.data([
          for (final u in current)
            if (byId[u.id] case final UnitPosition p) u.moved(p) else u,
        ]);
      case UnitUpdated() || IncidentUpdated():
        // Statuses changed: one debounced refetch (new units may be on duty).
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 800), () => refresh(silent: true));
      default:
        break;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _timer.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

final unitsProvider = StateNotifierProvider.autoDispose.family<UnitsController, AsyncValue<List<Unit>>, UnitsQuery>(
  (ref, query) => UnitsController(ref.watch(apiClientProvider), ref.watch(realtimeEventsProvider), query),
);

/// Key for [unitRouteProvider].
typedef UnitRouteKey = ({String unitId, LatLng to});

/// A unit with its route / ETA to a point (`/units/{id}?lat&lon`).
final unitRouteProvider = FutureProvider.autoDispose.family<Unit, UnitRouteKey>(
  (ref, key) => ref.watch(apiClientProvider).unit(key.unitId, to: key.to),
);
