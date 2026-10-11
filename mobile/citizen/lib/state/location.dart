import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import 'providers.dart';

enum LocationSource { demo, gps, manual }

/// Where the citizen is (or pretends to be, in the demo).
class UserLocation {
  const UserLocation({required this.point, required this.source, this.reason});

  const UserLocation.demo([this.reason]) : point = kDemoPoint, source = LocationSource.demo;

  final LatLng point;
  final LocationSource source;

  /// Why the demo point is used (shown to the user), if it is.
  final String? reason;

  bool get isDemo => source == LocationSource.demo;

  /// Line shown under «Моё местоположение».
  String get label => switch (source) {
    LocationSource.demo => kDemoAddress,
    LocationSource.gps => 'Геопозиция: ${_coords(point)}',
    LocationSource.manual => 'Точка на карте: ${_coords(point)}',
  };

  /// Prefill for the «Точный адрес» field: only the demo point has a known address.
  String get addressPrefill => isDemo ? kDemoAddress : '';

  static String _coords(LatLng p) => '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
}

/// Source of device fixes; null when unavailable or denied.
abstract class LocationService {
  Future<LatLng?> current();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LatLng?> current() async {
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => const GeolocatorLocationService());

class LocationController extends StateNotifier<UserLocation> {
  LocationController(this._ref) : super(const UserLocation.demo());

  final Ref _ref;
  bool _locating = false;

  GeoBounds get _area => _ref.read(metaProvider).valueOrNull?.bbox ?? kAlmatyBounds;

  /// Asks the device for a fix. Falls back to the demo point when the fix is
  /// unavailable, denied, or outside the service area.
  Future<UserLocation> locate() async {
    if (_locating) return state;
    _locating = true;
    try {
      final fix = await _ref.read(locationServiceProvider).current();
      if (!mounted) return state;
      if (fix == null) {
        state = const UserLocation.demo('Геолокация недоступна — показан демо-адрес.');
      } else if (!inServiceArea(fix, _area)) {
        state = const UserLocation.demo('Вы находитесь вне Алматы — показан демо-адрес.');
      } else {
        state = UserLocation(point: fix, source: LocationSource.gps);
      }
      return state;
    } finally {
      _locating = false;
    }
  }

  /// Moves the pin (long-press on the map). Returns false outside the city.
  bool setManual(LatLng point) {
    if (!inServiceArea(point, _area)) return false;
    state = UserLocation(point: point, source: LocationSource.manual);
    return true;
  }
}

final locationProvider = StateNotifierProvider<LocationController, UserLocation>((ref) => LocationController(ref));
