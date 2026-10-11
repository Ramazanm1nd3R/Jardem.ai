import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../logic/events.dart';
import '../logic/steps.dart';
import 'providers.dart';
import 'session.dart';

/// What the crew app knows about its own unit.
class CrewState {
  const CrewState({this.data, this.error, this.transportAt = const {}});

  /// Last good `/responder/me`.
  final ResponderState? data;

  /// Last refresh error; with non-null [data] it means «may be stale».
  final Object? error;

  /// When «Пациент загружен» was confirmed, by incident id (the incident
  /// timeline does not record it).
  final Map<String, DateTime> transportAt;

  Unit? get unit => data?.unit;
  Incident? get assignment => data?.assignment;
  UnitStatus get status => data?.unit.status ?? UnitStatus.unknown;
  bool get loading => data == null && error == null;

  /// A call waiting for «Принять вызов».
  Incident? get incoming => status == UnitStatus.assigned ? assignment : null;
}

/// `/responder/me` kept fresh: realtime events for this unit plus a 5 s poll.
class CrewController extends StateNotifier<CrewState> {
  CrewController(
    this._api,
    Stream<RealtimeEvent> events,
    this._clock, {
    required this.unitId,
    this.onUnauthorized,
    Duration pollEvery = const Duration(seconds: 5),
  }) : super(const CrewState()) {
    // Signed out: nothing to follow.
    if (unitId.isEmpty) return;
    _sub = events.listen(_onEvent);
    _timer = Timer.periodic(pollEvery, (_) => refresh());
    refresh();
  }

  final ApiClient _api;
  final DateTime Function() _clock;
  final String unitId;
  final void Function()? onUnauthorized;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _timer;
  bool _busy = false;
  bool _again = false;

  Future<void> refresh() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      final data = await _api.responderMe();
      if (mounted) state = CrewState(data: data, transportAt: state.transportAt);
    } catch (e) {
      if (e is ApiException && e.isUnauthorized) {
        onUnauthorized?.call();
      } else if (mounted) {
        state = CrewState(data: state.data, error: e, transportAt: state.transportAt);
      }
    } finally {
      _busy = false;
    }
    if (_again && mounted) {
      _again = false;
      await refresh();
    }
  }

  void _onEvent(RealtimeEvent event) {
    final data = state.data;
    if (event is UnitsMoved) {
      final p = ownPosition(event, unitId);
      if (p == null || data == null) return;
      // Position only: statuses change through the crew's own confirmations.
      state = CrewState(
        data: ResponderState(
          unit: data.unit.copyWith(lat: p.lat, lon: p.lon, heading: p.heading),
          assignment: data.assignment,
          counters: data.counters,
          unread: data.unread,
        ),
        error: state.error,
        transportAt: state.transportAt,
      );
    } else if (concernsCrew(event, unitId: unitId, incidentId: data?.assignment?.id)) {
      refresh();
    }
  }

  /// Runs one step of the state machine; throws [ApiException] (409 when the
  /// server is in a different state). The state is re-fetched either way.
  Future<void> perform(CrewStep step) async {
    final incidentId = state.assignment?.id;
    try {
      final onDuty = step.onDuty;
      if (onDuty != null) {
        await _api.responderShift(onDuty: onDuty);
      } else {
        await _api.responderAction(step.action!);
      }
      if (step == CrewStep.transport && incidentId != null && mounted) {
        state = CrewState(
          data: state.data,
          error: state.error,
          transportAt: {...state.transportAt, incidentId: _clock()},
        );
      }
    } finally {
      if (mounted) await refresh();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

/// Lives while a crew is signed in; re-created for another unit.
final crewProvider = StateNotifierProvider<CrewController, CrewState>((ref) {
  final unitId = ref.watch(sessionProvider.select((s) => s?.user.unitId)) ?? '';
  return CrewController(
    ref.watch(apiClientProvider),
    ref.watch(realtimeEventsProvider),
    ref.watch(clockProvider),
    unitId: unitId,
    onUnauthorized: () => ref.read(sessionProvider.notifier).signOut(),
  );
});
