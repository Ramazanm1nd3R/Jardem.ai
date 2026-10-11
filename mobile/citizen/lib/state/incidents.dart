import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import 'providers.dart';

/// The citizen's calls (`GET /incidents`), refreshed on incident events.
final incidentsProvider = FutureProvider.autoDispose<IncidentList>((ref) async {
  Timer? debounce;
  final sub = ref.watch(realtimeEventsProvider).where((e) => e is IncidentUpdated).listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 1), ref.invalidateSelf);
  });
  ref.onDispose(() {
    sub.cancel();
    debounce?.cancel();
  });
  return ref.watch(apiClientProvider).incidents();
});

/// Tracking state of one call.
class TrackingState {
  const TrackingState({this.incident, this.unit, this.error, this.loading = false});

  final Incident? incident;

  /// Last known crew — kept after the incident closes and its unit list empties.
  final Unit? unit;

  /// Last refresh error; with a non-null [incident] it means «data may be stale».
  final Object? error;
  final bool loading;

  TrackingState copyWith({Incident? incident, Object? error, bool? loading, bool clearError = false}) => TrackingState(
    incident: incident ?? this.incident,
    unit: unit,
    error: clearError ? null : (error ?? this.error),
    loading: loading ?? this.loading,
  );
}

/// Follows one incident: realtime events + a 5 s poll fallback.
class TrackingController extends StateNotifier<TrackingState> {
  TrackingController(
    this._api,
    Stream<RealtimeEvent> events,
    this.incidentId, {
    Duration pollEvery = const Duration(seconds: 5),
  }) : super(const TrackingState(loading: true)) {
    _sub = events.listen(_onEvent);
    _timer = Timer.periodic(pollEvery, (_) => refresh());
    refresh();
  }

  final ApiClient _api;
  final String incidentId;
  late final StreamSubscription<RealtimeEvent> _sub;
  late final Timer _timer;
  bool _busy = false;

  /// Active for a moment after each fetch, to throttle `units.moved` refreshes.
  Timer? _cooldown;

  Future<void> refresh() async {
    if (_busy) return;
    // A closed incident no longer changes.
    if (state.incident?.status.isClosed ?? false) {
      _timer.cancel();
      return;
    }
    _busy = true;
    try {
      final incident = await _api.incident(incidentId);
      _cooldown?.cancel();
      _cooldown = Timer(const Duration(milliseconds: 900), () {});
      if (mounted) {
        state = TrackingState(incident: incident, unit: incident.primaryUnit ?? state.unit);
      }
    } catch (e) {
      if (mounted) state = state.copyWith(error: e, loading: false);
    } finally {
      _busy = false;
    }
  }

  void _onEvent(RealtimeEvent event) {
    final incident = state.incident;
    switch (event) {
      case IncidentUpdated(:final incidentId) when incidentId == this.incidentId:
        refresh();
      case UnitUpdated(:final incidentId) when incidentId == this.incidentId:
        refresh();
      case UnitsMoved(:final units) when incident != null:
        final ids = {for (final u in incident.units) u.id};
        if (!units.any((p) => ids.contains(p.id))) return;
        // Our crew moved: refresh route/ETA, at most about once a second.
        if (!(_cooldown?.isActive ?? false)) refresh();
      default:
        break;
    }
  }

  /// `POST /incidents/{id}/cancel`; throws [ApiException] (409 once on scene).
  Future<void> cancel() async {
    final incident = await _api.cancelIncident(incidentId);
    if (mounted) {
      state = TrackingState(incident: incident, unit: incident.primaryUnit ?? state.unit);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _timer.cancel();
    _cooldown?.cancel();
    super.dispose();
  }
}

final trackingProvider = StateNotifierProvider.autoDispose.family<TrackingController, TrackingState, String>(
  (ref, id) => TrackingController(ref.watch(apiClientProvider), ref.watch(realtimeEventsProvider), id),
);
