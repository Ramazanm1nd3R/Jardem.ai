import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../logic/closures.dart';
import 'map.dart';
import 'providers.dart';

const String kClosuresKey = 'jardem.responder.closures';

/// Ids of the closures reported from this device (only these can be lifted
/// here: `/traffic` does not say who reported a closure).
class MyClosuresController extends StateNotifier<Set<String>> {
  MyClosuresController(this._ref) : super({...?_ref.read(sharedPreferencesProvider).getStringList(kClosuresKey)});

  final Ref _ref;

  void _save(Set<String> ids) {
    state = ids;
    _ref.read(sharedPreferencesProvider).setStringList(kClosuresKey, ids.toList()..sort());
  }

  /// `POST /traffic/closures`; throws [ApiException].
  Future<void> report(LatLng at, String reason) async {
    final closure = await _ref.read(apiClientProvider).reportClosure(at, reason: reason, minutes: kClosureMinutes);
    if (mounted) _save(withClosure(state, closure.id));
    _ref.invalidate(trafficProvider);
  }

  /// `DELETE /traffic/closures/{id}`; throws [ApiException].
  Future<void> lift(String id) async {
    try {
      await _ref.read(apiClientProvider).liftClosure(id);
    } on ApiException catch (e) {
      // Already gone on the server: forget it as well.
      if (!e.isNotFound) rethrow;
    }
    if (mounted) _save(withoutClosure(state, id));
    _ref.invalidate(trafficProvider);
  }

  /// Drops ids that are no longer active.
  void sync(List<RoadClosure> active) {
    final kept = pruneClosures(state, active);
    if (kept.length != state.length) _save(kept);
  }
}

final myClosuresProvider = StateNotifierProvider<MyClosuresController, Set<String>>((ref) => MyClosuresController(ref));
