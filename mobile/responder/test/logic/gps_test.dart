import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/gps.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const inside = LatLng(43.2445, 76.9457);
  const astana = LatLng(51.1694, 71.4491);

  group('acceptFix', () {
    test('inside the city, sharing on, on shift', () {
      expect(acceptFix(sharing: true, onDuty: true, fix: inside), isTrue);
    });

    test('never when sharing is off', () {
      expect(acceptFix(sharing: false, onDuty: true, fix: inside), isFalse);
    });

    test('never when off shift', () {
      expect(acceptFix(sharing: true, onDuty: false, fix: inside), isFalse);
    });

    test('never without a fix or outside the bbox', () {
      expect(acceptFix(sharing: true, onDuty: true, fix: null), isFalse);
      expect(acceptFix(sharing: true, onDuty: true, fix: astana), isFalse);
      expect(acceptFix(sharing: true, onDuty: true, fix: const LatLng(0, 0)), isFalse);
    });

    test('uses the given area', () {
      const area = GeoBounds(51, 71, 52, 72);
      expect(acceptFix(sharing: true, onDuty: true, fix: astana, area: area), isTrue);
      expect(acceptFix(sharing: true, onDuty: true, fix: inside, area: area), isFalse);
    });

    test('the bbox edge is inside', () {
      expect(acceptFix(sharing: true, onDuty: true, fix: LatLng(kAlmatyBounds.minLat, kAlmatyBounds.minLon)), isTrue);
      expect(
        acceptFix(sharing: true, onDuty: true, fix: LatLng(kAlmatyBounds.minLat - 0.0001, kAlmatyBounds.minLon)),
        isFalse,
      );
    });
  });

  test('reported speed', () {
    expect(reportedSpeed(null), isNull);
    expect(reportedSpeed(double.nan), isNull);
    expect(reportedSpeed(-1), isNull);
    expect(reportedSpeed(-0.01), isNull);
    expect(reportedSpeed(0), 0);
    expect(reportedSpeed(13.9), 13.9);
    expect(reportedSpeed(kMaxSpeedMps), kMaxSpeedMps);
    expect(reportedSpeed(kMaxSpeedMps + 0.1), isNull);
    expect(kMaxSpeedMps, 70);
  });

  test('hint under the switch', () {
    expect(gpsHint(sharing: false, onDuty: true), 'Выключено: сервер моделирует движение машины по маршруту.');
    expect(gpsHint(sharing: false, onDuty: false, lastFixAccepted: true), startsWith('Выключено'));
    expect(gpsHint(sharing: true, onDuty: false), 'Включено: координаты начнут передаваться после выхода на смену.');
    expect(gpsHint(sharing: true, onDuty: false, lastFixAccepted: true), contains('после выхода на смену'));
    expect(gpsHint(sharing: true, onDuty: true), 'Включено: ожидание координат устройства…');
    expect(
      gpsHint(sharing: true, onDuty: true, lastFixAccepted: true),
      'Включено: координаты передаются каждые 5 секунд.',
    );
    expect(
      gpsHint(sharing: true, onDuty: true, lastFixAccepted: false),
      'Нет координат в пределах Алматы — движение моделирует сервер.',
    );
  });
}
