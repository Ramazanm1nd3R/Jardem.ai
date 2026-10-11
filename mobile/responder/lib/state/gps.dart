import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../logic/gps.dart';
import 'crew.dart';
import 'providers.dart';

const String kGpsKey = 'jardem.responder.share_gps';

class GpsFix {
  const GpsFix(this.point, {this.speedMps});
  final LatLng point;
  final double? speedMps;
}

/// Source of device fixes; null when unavailable or denied.
abstract class FixSource {
  Future<GpsFix?> current();
}

class GeolocatorFixSource implements FixSource {
  const GeolocatorFixSource();

  @override
  Future<GpsFix?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 4)),
      );
      return GpsFix(LatLng(p.latitude, p.longitude), speedMps: p.speed);
    } catch (_) {
      return null;
    }
  }
}

final fixSourceProvider = Provider<FixSource>((ref) => const GeolocatorFixSource());

class GpsState {
  const GpsState({this.sharing = false, this.lastFixAccepted, this.sent = 0});

  /// The «Передавать геопозицию» switch (off by default in the demo).
  final bool sharing;

  /// Whether the latest attempt produced a fix that was sent; null before any.
  final bool? lastFixAccepted;

  /// How many fixes were posted since the switch was turned on.
  final int sent;
}

/// Posts real GPS fixes to `/responder/location` every ~5 s while the switch
/// is on and the crew is on shift. Fixes outside the city bbox are never sent.
class GpsController extends StateNotifier<GpsState> {
  GpsController(this._ref, {this.every = const Duration(seconds: 5)})
    : super(GpsState(sharing: _ref.read(sharedPreferencesProvider).getBool(kGpsKey) ?? false)) {
    if (state.sharing) _start();
  }

  final Ref _ref;
  final Duration every;
  Timer? _timer;
  bool _busy = false;

  void _start() {
    _timer ??= Timer.periodic(every, (_) => tick());
  }

  Future<void> setSharing(bool on) async {
    await _ref.read(sharedPreferencesProvider).setBool(kGpsKey, on);
    if (!mounted) return;
    state = GpsState(sharing: on);
    if (on) {
      _start();
      await tick();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// One attempt: read a fix, check it, post it.
  Future<void> tick() async {
    if (_busy || !state.sharing) return;
    final onDuty = _ref.read(crewProvider).unit?.onDuty ?? false;
    if (!onDuty) return;
    _busy = true;
    try {
      final fix = await _ref.read(fixSourceProvider).current();
      if (!mounted || !state.sharing) return;
      final area = _ref.read(metaProvider).valueOrNull?.bbox ?? kAlmatyBounds;
      if (!acceptFix(sharing: state.sharing, onDuty: onDuty, fix: fix?.point, area: area)) {
        state = GpsState(sharing: true, lastFixAccepted: false, sent: state.sent);
        return;
      }
      await _ref.read(apiClientProvider).responderLocation(fix!.point, speedMps: reportedSpeed(fix.speedMps));
      if (mounted) state = GpsState(sharing: true, lastFixAccepted: true, sent: state.sent + 1);
    } on ApiException {
      // A lost request is not worth a message; the next tick tries again.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final gpsProvider = StateNotifierProvider<GpsController, GpsState>((ref) => GpsController(ref));
