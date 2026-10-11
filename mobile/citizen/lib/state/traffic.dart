import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import 'providers.dart';

/// Whether the traffic layer is shown on the home map (on by default).
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
