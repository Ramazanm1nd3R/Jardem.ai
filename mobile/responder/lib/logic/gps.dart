/// Decides which GPS fixes may be sent to `/responder/location`.
library;

import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

/// Anything faster is a glitch, not an ambulance.
const double kMaxSpeedMps = 70;

/// A fix is sent only when sharing is switched on, the crew is on shift and
/// the point lies inside the service area (the `/meta` bbox of Almaty).
bool acceptFix({required bool sharing, required bool onDuty, required LatLng? fix, GeoBounds area = kAlmatyBounds}) =>
    sharing && onDuty && inServiceArea(fix, area);

/// Speed to report: null when the device gave none or nonsense.
double? reportedSpeed(double? mps) {
  if (mps == null || mps.isNaN || mps < 0 || mps > kMaxSpeedMps) return null;
  return mps;
}

/// One line under the «Передавать геопозицию» switch.
String gpsHint({required bool sharing, required bool onDuty, bool? lastFixAccepted}) {
  if (!sharing) return 'Выключено: сервер моделирует движение машины по маршруту.';
  if (!onDuty) return 'Включено: координаты начнут передаваться после выхода на смену.';
  return switch (lastFixAccepted) {
    true => 'Включено: координаты передаются каждые 5 секунд.',
    false => 'Нет координат в пределах Алматы — движение моделирует сервер.',
    null => 'Включено: ожидание координат устройства…',
  };
}
