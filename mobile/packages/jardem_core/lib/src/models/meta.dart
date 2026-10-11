import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'enums.dart';
import 'json.dart';

const String kDefaultDisclaimer = 'Демо-режим. В реальной экстренной ситуации звоните 112';

/// `GET /meta`: city, service area, disclaimer and the real emergency numbers.
class Meta {
  const Meta({
    this.city = 'Алматы',
    this.center = kDemoPoint,
    this.bbox = kAlmatyBounds,
    this.demo = true,
    this.disclaimer = kDefaultDisclaimer,
    this.emergencyPhone = '112',
    this.phones = const {},
    this.strategy = '',
    this.strategies = const [],
    this.autoDispatch = true,
    this.simSpeed = 1,
    this.appUrl = '',
  });

  factory Meta.fromJson(Json j) {
    final c = asJson(j['center']);
    final lat = dblOrNull(c, 'lat'), lon = dblOrNull(c, 'lon');
    return Meta(
      city: str(j, 'city', 'Алматы'),
      center: lat != null && lon != null ? LatLng(lat, lon) : kDemoPoint,
      bbox: GeoBounds.fromList(j['bbox']) ?? kAlmatyBounds,
      demo: boolean(j, 'demo', true),
      disclaimer: str(j, 'disclaimer', kDefaultDisclaimer),
      emergencyPhone: str(j, 'emergency_phone', '112'),
      phones: {
        for (final e in asJson(j['phones']).entries)
          if (e.value != null) e.key: e.value.toString(),
      },
      strategy: str(j, 'strategy'),
      strategies: strings(j['strategies']),
      autoDispatch: boolean(j, 'auto_dispatch', true),
      simSpeed: dbl(j, 'sim_speed', 1),
      appUrl: str(j, 'app_url'),
    );
  }

  final String city;
  final LatLng center;
  final GeoBounds bbox;
  final bool demo;
  final String disclaimer;
  final String emergencyPhone;
  final Map<String, String> phones;
  final String strategy;
  final List<String> strategies;
  final bool autoDispatch;
  final double simSpeed;
  final String appUrl;

  /// Direct number of [service], falling back to the built-in table.
  String phoneOf(ServiceType service) => phones[service.id] ?? service.phone;
}

class Health {
  const Health({this.status = '', this.uptimeS = 0, this.database = false, this.redis = false, this.units = 0});

  factory Health.fromJson(Json j) => Health(
    status: str(j, 'status'),
    uptimeS: integer(j, 'uptime_s'),
    database: boolean(j, 'database'),
    redis: boolean(j, 'redis'),
    units: integer(j, 'units'),
  );

  final String status;
  final int uptimeS;
  final bool database;
  final bool redis;
  final int units;

  bool get ok => status == 'ok';
}

class ServiceStats {
  const ServiceStats({this.activeIncidents = 0, this.units = 0, this.unitsFree = 0});

  factory ServiceStats.fromJson(Json j) => ServiceStats(
    activeIncidents: integer(j, 'active_incidents'),
    units: integer(j, 'units'),
    unitsFree: integer(j, 'units_free'),
  );

  final int activeIncidents;
  final int units;
  final int unitsFree;
}

/// `GET /stats`.
class Stats {
  const Stats({
    this.services = const {},
    this.activeIncidents = 0,
    this.departments = 0,
    this.meanArrivalS,
    this.served = 0,
    this.trafficIndex = 0,
    this.strategy = '',
  });

  factory Stats.fromJson(Json j) => Stats(
    services: {
      for (final e in asJson(j['services']).entries)
        if (ServiceType.tryParse(e.key) case final ServiceType s) s: ServiceStats.fromJson(asJson(e.value)),
    },
    activeIncidents: integer(j, 'active_incidents'),
    departments: integer(j, 'departments'),
    meanArrivalS: intOrNull(j, 'mean_arrival_s'),
    served: integer(j, 'served'),
    trafficIndex: integer(j, 'traffic_index'),
    strategy: str(j, 'strategy'),
  );

  final Map<ServiceType, ServiceStats> services;
  final int activeIncidents;
  final int departments;
  final int? meanArrivalS;
  final int served;
  final int trafficIndex;
  final String strategy;
}

/// `POST /dispatch/compare`: what each strategy would send.
class DispatchComparison {
  const DispatchComparison({this.picks = const {}, this.candidates = const []});

  factory DispatchComparison.fromJson(Json j) => DispatchComparison(
    picks: {for (final e in asJson(j['picks']).entries) e.key: strings(e.value)},
    candidates: listOf(j['candidates'], (c) => c),
  );

  /// Strategy name → picked unit ids.
  final Map<String, List<String>> picks;

  /// Ranked candidates: unit fields plus `cost`, `coverage_loss_s`, `overqualified`.
  final List<Json> candidates;
}
