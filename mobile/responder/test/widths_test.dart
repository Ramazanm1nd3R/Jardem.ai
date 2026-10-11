import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';

import 'support.dart';

/// Every screen at the narrowest and the widest supported phone width, in the
/// states with the most content, for both an ambulance and a fire crew.
void main() {
  const routes = [
    '/home',
    '/map',
    '/calls',
    '/messages',
    '/profile',
    '/call',
    '/crew',
    '/crew?tab=1',
    '/crew?tab=2',
    '/shift',
    '/closure',
    '/about',
  ];

  for (final width in const [360.0, 390.0, 430.0]) {
    for (final service in const [ServiceType.ambulance, ServiceType.fire]) {
      for (final phase in const ['off_duty', 'assigned', 'en_route', 'on_scene']) {
        testWidgets('no overflow: ${width.toInt()} px · ${service.id} · $phase', (tester) async {
          final h = Harness(phase: phase, service: service)
            ..api.extraInfo = 'Доступ на территорию через шлагбаум. Код въезда: 3587. Встречает заявитель.';
          await h.pump(tester, size: Size(width, 640));
          for (final route in routes) {
            await h.go(tester, route);
            expect(tester.takeException(), isNull, reason: '$route at $width');
          }
        });
      }
    }
  }
}
