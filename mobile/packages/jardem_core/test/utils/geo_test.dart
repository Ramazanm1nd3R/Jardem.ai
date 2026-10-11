import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('lonLatToLatLng', () {
    test('swaps GeoJSON order', () {
      expect(lonLatToLatLng([76.9457, 43.2445]), const LatLng(43.2445, 76.9457));
      expect(lonLatToLatLng([76, 43]), const LatLng(43, 76));
    });

    test('extra coordinates (altitude) are ignored', () {
      expect(lonLatToLatLng([76.9, 43.2, 800]), const LatLng(43.2, 76.9));
    });

    test('malformed pairs give null', () {
      expect(lonLatToLatLng(null), isNull);
      expect(lonLatToLatLng('76,43'), isNull);
      expect(lonLatToLatLng([]), isNull);
      expect(lonLatToLatLng([76.9]), isNull);
      expect(lonLatToLatLng(['76.9', 43.2]), isNull);
      expect(lonLatToLatLng([76.9, '43.2']), isNull);
      expect(lonLatToLatLng([76.9, null]), isNull);
    });
  });

  group('lineFromJson', () {
    test('converts and skips bad entries', () {
      expect(
        lineFromJson([
          [76.93822, 43.23323],
          'oops',
          [76.93853],
          [76.93853, 43.23337],
        ]),
        const [LatLng(43.23323, 76.93822), LatLng(43.23337, 76.93853)],
      );
    });

    test('non-lists give an empty line', () {
      expect(lineFromJson(null), isEmpty);
      expect(lineFromJson({'a': 1}), isEmpty);
      expect(lineFromJson(const []), isEmpty);
    });
  });

  group('haversineM', () {
    test('zero for identical points', () {
      expect(haversineM(kDemoPoint, kDemoPoint), 0);
    });

    test('one degree of latitude is about 111.2 km', () {
      expect(haversineM(const LatLng(43, 76), const LatLng(44, 76)), closeTo(111195, 5));
    });

    test('one degree of longitude shrinks with latitude', () {
      expect(haversineM(const LatLng(0, 76), const LatLng(0, 77)), closeTo(111195, 5));
      expect(haversineM(const LatLng(43.2445, 76), const LatLng(43.2445, 77)), closeTo(80995, 30));
      expect(haversineM(const LatLng(60, 76), const LatLng(60, 77)), closeTo(55597, 10));
    });

    test('is symmetric', () {
      const a = LatLng(43.2331, 76.9382), b = LatLng(43.2445, 76.9457);
      expect(haversineM(a, b), closeTo(haversineM(b, a), 1e-6));
      expect(haversineM(a, b), closeTo(1406, 5));
    });

    test('diagonal combines both axes', () {
      // Roughly sqrt(111195² + 80300²) for one degree each way near Almaty.
      expect(haversineM(const LatLng(43, 76), const LatLng(44, 77)), closeTo(137330, 300));
    });

    test('antipodes are half the circumference', () {
      expect(haversineM(const LatLng(0, 0), const LatLng(0, 180)), closeTo(3.141592653589793 * kEarthRadiusM, 1));
      expect(kEarthRadiusM, 6371000);
    });
  });

  group('polylineLengthM', () {
    test('short lists are zero', () {
      expect(polylineLengthM(const []), 0);
      expect(polylineLengthM(const [kDemoPoint]), 0);
    });

    test('sums consecutive segments', () {
      const a = LatLng(43, 76), b = LatLng(43.01, 76), c = LatLng(43.01, 76.01);
      expect(polylineLengthM(const [a, b]), closeTo(haversineM(a, b), 1e-9));
      expect(polylineLengthM(const [a, b, c]), closeTo(haversineM(a, b) + haversineM(b, c), 1e-9));
      expect(polylineLengthM(const [a, b, c]), greaterThan(haversineM(a, c)));
      expect(polylineLengthM(const [a, b, a]), closeTo(2 * haversineM(a, b), 1e-9));
    });
  });

  group('GeoBounds', () {
    const box = GeoBounds(43.1, 76.7, 43.4, 77.1);

    test('fromList parses the API order', () {
      expect(GeoBounds.fromList([43.118165, 76.738513, 43.397272, 77.07995]), kAlmatyBounds);
      expect(GeoBounds.fromList([43, 76, 44, 77]), const GeoBounds(43, 76, 44, 77));
    });

    test('fromList rejects malformed input', () {
      expect(GeoBounds.fromList(null), isNull);
      expect(GeoBounds.fromList('1,2,3,4'), isNull);
      expect(GeoBounds.fromList([1, 2, 3]), isNull);
      expect(GeoBounds.fromList([1, 2, 3, 4, 5]), isNull);
      expect(GeoBounds.fromList([1, 2, '3', 4]), isNull);
      expect(GeoBounds.fromList([1, 2, 3, null]), isNull);
    });

    test('corners and centre', () {
      expect(box.southWest, const LatLng(43.1, 76.7));
      expect(box.northEast, const LatLng(43.4, 77.1));
      expect(box.center.latitude, closeTo(43.25, 1e-9));
      expect(box.center.longitude, closeTo(76.9, 1e-9));
    });

    test('contains is inclusive on every edge', () {
      expect(box.contains(const LatLng(43.25, 76.9)), isTrue);
      expect(box.contains(const LatLng(43.1, 76.7)), isTrue);
      expect(box.contains(const LatLng(43.4, 77.1)), isTrue);
      expect(box.contains(const LatLng(43.1, 77.1)), isTrue);
      expect(box.contains(const LatLng(43.4, 76.7)), isTrue);
    });

    test('contains rejects each side separately', () {
      expect(box.contains(const LatLng(43.0999, 76.9)), isFalse);
      expect(box.contains(const LatLng(43.4001, 76.9)), isFalse);
      expect(box.contains(const LatLng(43.25, 76.6999)), isFalse);
      expect(box.contains(const LatLng(43.25, 77.1001)), isFalse);
    });

    test('toQuery matches the /traffic bbox parameter', () {
      expect(box.toQuery(), '43.1,76.7,43.4,77.1');
      expect(box.toString(), 'GeoBounds(43.1,76.7,43.4,77.1)');
    });

    test('equality and hashCode compare all four edges', () {
      expect(box, const GeoBounds(43.1, 76.7, 43.4, 77.1));
      expect(box.hashCode, const GeoBounds(43.1, 76.7, 43.4, 77.1).hashCode);
      expect(box.hashCode, Object.hash(43.1, 76.7, 43.4, 77.1));
      expect(box == const GeoBounds(43.2, 76.7, 43.4, 77.1), isFalse);
      expect(box == const GeoBounds(43.1, 76.8, 43.4, 77.1), isFalse);
      expect(box == const GeoBounds(43.1, 76.7, 43.5, 77.1), isFalse);
      expect(box == const GeoBounds(43.1, 76.7, 43.4, 77.2), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(box == 'GeoBounds', isFalse);
    });
  });

  group('boundsOf', () {
    test('empty input', () {
      expect(boundsOf(const []), isNull);
    });

    test('single point is a degenerate box', () {
      expect(boundsOf(const [kDemoPoint]), const GeoBounds(43.2445, 76.9457, 43.2445, 76.9457));
    });

    test('covers all points regardless of order', () {
      const pts = [LatLng(43.25, 76.95), LatLng(43.20, 76.99), LatLng(43.31, 76.90), LatLng(43.22, 76.93)];
      expect(boundsOf(pts), const GeoBounds(43.20, 76.90, 43.31, 76.99));
      expect(boundsOf(pts.reversed), const GeoBounds(43.20, 76.90, 43.31, 76.99));
    });
  });

  group('inServiceArea', () {
    test('demo point is inside Almaty', () {
      expect(inServiceArea(kDemoPoint), isTrue);
      expect(kDemoPoint, const LatLng(43.2445, 76.9457));
      expect(kDemoAddress, 'ул. Назарбаева, 125, Алматы');
    });

    test('other cities and null are outside', () {
      expect(inServiceArea(const LatLng(51.1694, 71.4491)), isFalse); // Astana
      expect(inServiceArea(const LatLng(50, 70)), isFalse);
      expect(inServiceArea(null), isFalse);
    });

    test('uses the given area', () {
      const tiny = GeoBounds(0, 0, 1, 1);
      expect(inServiceArea(kDemoPoint, tiny), isFalse);
      expect(inServiceArea(const LatLng(0.5, 0.5), tiny), isTrue);
    });

    test('default area equals /meta bbox of the live API', () {
      expect(kAlmatyBounds, const GeoBounds(43.118165, 76.738513, 43.397272, 77.07995));
    });
  });

  group('lerpLatLng', () {
    const a = LatLng(43, 76), b = LatLng(44, 78);

    test('endpoints and midpoint', () {
      expect(lerpLatLng(a, b, 0), a);
      expect(lerpLatLng(a, b, 1), b);
      expect(lerpLatLng(a, b, 0.5), const LatLng(43.5, 77));
      expect(lerpLatLng(a, b, 0.25), const LatLng(43.25, 76.5));
    });

    test('clamps t', () {
      expect(lerpLatLng(a, b, -0.5), a);
      expect(lerpLatLng(a, b, 1.5), b);
    });

    test('works in the opposite direction', () {
      expect(lerpLatLng(b, a, 0.25), const LatLng(43.75, 77.5));
    });
  });
}
