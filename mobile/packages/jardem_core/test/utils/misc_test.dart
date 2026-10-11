import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';

void main() {
  group('TrafficLevel', () {
    test('parses every wire value', () {
      expect(TrafficLevel.parse('free'), TrafficLevel.free);
      expect(TrafficLevel.parse('slow'), TrafficLevel.slow);
      expect(TrafficLevel.parse('jam'), TrafficLevel.jam);
      expect(TrafficLevel.parse('heavy'), TrafficLevel.heavy);
      expect(TrafficLevel.parse('closed'), TrafficLevel.closed);
    });

    test('unknown values are treated as free', () {
      expect(TrafficLevel.parse(null), TrafficLevel.free);
      expect(TrafficLevel.parse('gridlock'), TrafficLevel.free);
      expect(TrafficLevel.parse(3), TrafficLevel.free);
    });

    test('colours: green, yellow, orange, red, dark grey', () {
      expect(TrafficLevel.free.color, const Color(0xFF2FB56A));
      expect(TrafficLevel.slow.color, const Color(0xFFF2C230));
      expect(TrafficLevel.jam.color, const Color(0xFFF5821F));
      expect(TrafficLevel.heavy.color, const Color(0xFFE03131));
      expect(TrafficLevel.closed.color, const Color(0xFF495057));
    });

    test('only closed roads are dashed', () {
      expect(TrafficLevel.values.where((l) => l.dashed), [TrafficLevel.closed]);
    });

    test('labels', () {
      expect(TrafficLevel.values.map((l) => l.label), ['Свободно', 'Плотно', 'Затор', 'Пробка', 'Перекрыто']);
    });

    test('trafficLevelColor accepts enums and wire strings', () {
      expect(trafficLevelColor(TrafficLevel.heavy), TrafficLevel.heavy.color);
      expect(trafficLevelColor('jam'), TrafficLevel.jam.color);
      expect(trafficLevelColor('closed'), TrafficLevel.closed.color);
      expect(trafficLevelColor(null), TrafficLevel.free.color);
      expect(trafficLevelColor('nonsense'), TrafficLevel.free.color);
    });
  });

  group('traffic index', () {
    test('level thresholds', () {
      expect(trafficIndexLevel(null), TrafficLevel.free);
      expect(trafficIndexLevel(0), TrafficLevel.free);
      expect(trafficIndexLevel(3), TrafficLevel.free);
      expect(trafficIndexLevel(3.9), TrafficLevel.free);
      expect(trafficIndexLevel(4), TrafficLevel.slow);
      expect(trafficIndexLevel(5), TrafficLevel.slow);
      expect(trafficIndexLevel(5.9), TrafficLevel.slow);
      expect(trafficIndexLevel(6), TrafficLevel.jam);
      expect(trafficIndexLevel(7), TrafficLevel.jam);
      expect(trafficIndexLevel(7.9), TrafficLevel.jam);
      expect(trafficIndexLevel(8), TrafficLevel.heavy);
      expect(trafficIndexLevel(10), TrafficLevel.heavy);
    });

    test('label is clamped and rounded', () {
      expect(trafficIndexLabel(4), 'Пробки 4/10');
      expect(trafficIndexLabel(0), 'Пробки 0/10');
      expect(trafficIndexLabel(10), 'Пробки 10/10');
      expect(trafficIndexLabel(null), 'Пробки 0/10');
      expect(trafficIndexLabel(-3), 'Пробки 0/10');
      expect(trafficIndexLabel(14), 'Пробки 10/10');
      expect(trafficIndexLabel(6.6), 'Пробки 7/10');
      expect(trafficIndexLabel(6.4), 'Пробки 6/10');
      expect(trafficIndexLabel(1), 'Пробки 1/10');
      expect(trafficIndexLabel(9), 'Пробки 9/10');
    });
  });

  group('citizenStepper', () {
    const done = StepPhase.done, active = StepPhase.active, pending = StepPhase.pending;

    test('steps', () {
      expect(kCitizenSteps, ['Принят', 'Экипаж выехал', 'В пути', 'Прибытие']);
    });

    test('new / assigned: only the first step is done', () {
      expect(citizenStepper(IncidentStatus.created), [done, pending, pending, pending]);
      expect(citizenStepper(IncidentStatus.assigned), [done, pending, pending, pending]);
    });

    test('en_route: two done, «В пути» active', () {
      expect(citizenStepper(IncidentStatus.enRoute), [done, done, active, pending]);
    });

    test('on_scene / resolved: everything done', () {
      expect(citizenStepper(IncidentStatus.onScene), [done, done, done, done]);
      expect(citizenStepper(IncidentStatus.resolved), [done, done, done, done]);
    });

    test('cancelled / unknown: only the first step', () {
      expect(citizenStepper(IncidentStatus.cancelled), [done, pending, pending, pending]);
      expect(citizenStepper(IncidentStatus.unknown), [done, pending, pending, pending]);
    });

    test('always four entries', () {
      for (final s in IncidentStatus.values) {
        expect(citizenStepper(s), hasLength(4));
      }
    });

    test('titles', () {
      expect(citizenStatusTitle(IncidentStatus.created), 'Вызов принят');
      expect(citizenStatusTitle(IncidentStatus.assigned), 'Экипаж назначен');
      expect(citizenStatusTitle(IncidentStatus.enRoute), 'Экипаж в пути');
      expect(citizenStatusTitle(IncidentStatus.onScene), 'Экипаж на месте');
      expect(citizenStatusTitle(IncidentStatus.resolved), 'Вызов завершён');
      expect(citizenStatusTitle(IncidentStatus.cancelled), 'Вызов отменён');
      expect(citizenStatusTitle(IncidentStatus.unknown), 'Вызов принят');
    });
  });

  group('timeToArrivalS', () {
    final created = DateTime.utc(2026, 10, 11, 8, 0, 0);

    test('prefers the server value', () {
      expect(
        timeToArrivalS(firstArrivalS: 173, createdAt: created, arrivedAt: created.add(const Duration(seconds: 5))),
        173,
      );
      expect(timeToArrivalS(firstArrivalS: 0), 0);
    });

    test('falls back to the timeline', () {
      expect(timeToArrivalS(createdAt: created, arrivedAt: created.add(const Duration(seconds: 95))), 95);
      expect(timeToArrivalS(createdAt: created, arrivedAt: created), 0);
    });

    test('unknown when a timestamp is missing', () {
      expect(timeToArrivalS(), isNull);
      expect(timeToArrivalS(createdAt: created), isNull);
      expect(timeToArrivalS(arrivedAt: created), isNull);
    });

    test('negative spans are rejected', () {
      expect(timeToArrivalS(createdAt: created, arrivedAt: created.subtract(const Duration(seconds: 1))), isNull);
    });
  });

  group('reconnectDelay', () {
    test('doubles from one second', () {
      expect(reconnectDelay(0), const Duration(seconds: 1));
      expect(reconnectDelay(1), const Duration(seconds: 2));
      expect(reconnectDelay(2), const Duration(seconds: 4));
      expect(reconnectDelay(3), const Duration(seconds: 8));
      expect(reconnectDelay(4), const Duration(seconds: 16));
    });

    test('is capped at 30 s', () {
      expect(reconnectDelay(5), const Duration(seconds: 30));
      expect(reconnectDelay(6), const Duration(seconds: 30));
      expect(reconnectDelay(20), const Duration(seconds: 30));
      expect(reconnectDelay(21), const Duration(seconds: 30));
      expect(reconnectDelay(1000), const Duration(seconds: 30));
    });

    test('negative attempts behave like the first', () {
      expect(reconnectDelay(-1), const Duration(seconds: 1));
    });

    test('custom base and cap', () {
      const base = Duration(milliseconds: 100), max = Duration(milliseconds: 450);
      expect(reconnectDelay(0, base: base, max: max), base);
      expect(reconnectDelay(1, base: base, max: max), const Duration(milliseconds: 200));
      expect(reconnectDelay(2, base: base, max: max), const Duration(milliseconds: 400));
      expect(reconnectDelay(3, base: base, max: max), max);
    });

    test('a delay exactly at the cap returns the cap', () {
      const base = Duration(milliseconds: 100), max = Duration(milliseconds: 400);
      expect(reconnectDelay(2, base: base, max: max), max);
    });

    test('exponent is limited so huge attempts cannot overflow', () {
      const base = Duration(milliseconds: 1), max = Duration(days: 100000);
      expect(reconnectDelay(20, base: base, max: max), const Duration(milliseconds: 1 << 20));
      expect(reconnectDelay(21, base: base, max: max), const Duration(milliseconds: 1 << 20));
      expect(reconnectDelay(64, base: base, max: max), const Duration(milliseconds: 1 << 20));
      expect(reconnectDelay(19, base: base, max: max), const Duration(milliseconds: 1 << 19));
    });
  });

  group('resolveApiBase', () {
    final page = Uri.parse('https://jardem.example/app/citizen/#/map');

    test('explicit override wins everywhere', () {
      expect(
        resolveApiBase(override: 'http://192.168.1.5:8080/api/v1', isWeb: true, isAndroid: false, pageUri: page),
        'http://192.168.1.5:8080/api/v1',
      );
      expect(resolveApiBase(override: ' http://h/api/v1// ', isWeb: false, isAndroid: true), 'http://h/api/v1');
    });

    test('web uses the page origin', () {
      expect(resolveApiBase(isWeb: true, isAndroid: false, pageUri: page), 'https://jardem.example/api/v1');
      expect(
        resolveApiBase(isWeb: true, isAndroid: false, pageUri: Uri.parse('http://localhost:8080/app/citizen/')),
        'http://localhost:8080/api/v1',
      );
    });

    test('page uri is ignored off the web', () {
      expect(resolveApiBase(isWeb: false, isAndroid: false, pageUri: page), 'http://localhost:8080/api/v1');
      expect(resolveApiBase(isWeb: false, isAndroid: true, pageUri: page), 'http://10.0.2.2:8080/api/v1');
    });

    test('web without a usable page uri falls back to localhost', () {
      expect(resolveApiBase(isWeb: true, isAndroid: false), 'http://localhost:8080/api/v1');
      expect(
        resolveApiBase(isWeb: true, isAndroid: false, pageUri: Uri.parse('/relative')),
        'http://localhost:8080/api/v1',
      );
      expect(
        resolveApiBase(isWeb: true, isAndroid: false, pageUri: Uri.parse('file:///index.html')),
        'http://localhost:8080/api/v1',
      );
    });

    test('native defaults', () {
      expect(resolveApiBase(isWeb: false, isAndroid: true), 'http://10.0.2.2:8080/api/v1');
      expect(resolveApiBase(isWeb: false, isAndroid: false), 'http://localhost:8080/api/v1');
      expect(resolveApiBase(override: '   ', isWeb: false, isAndroid: false), 'http://localhost:8080/api/v1');
      expect(kApiPath, '/api/v1');
    });
  });

  group('wsUrlFor', () {
    test('http → ws, https → wss', () {
      expect(wsUrlFor('http://localhost:8080/api/v1'), 'ws://localhost:8080/api/v1/ws');
      expect(wsUrlFor('https://jardem.example/api/v1'), 'wss://jardem.example/api/v1/ws');
      expect(wsUrlFor('http://10.0.2.2:8080/api/v1'), 'ws://10.0.2.2:8080/api/v1/ws');
    });

    test('trailing slashes are ignored', () {
      expect(wsUrlFor('http://localhost:8080/api/v1/'), 'ws://localhost:8080/api/v1/ws');
      expect(wsUrlFor('http://localhost:8080/api/v1///'), 'ws://localhost:8080/api/v1/ws');
    });

    test('already-websocket bases keep their security', () {
      expect(wsUrlFor('wss://h/api/v1'), 'wss://h/api/v1/ws');
      expect(wsUrlFor('ws://h/api/v1'), 'ws://h/api/v1/ws');
    });
  });

  group('photoAsset', () {
    test('thumbnail by default', () {
      expect(photoAsset('ambulance_kz_1'), 'assets/images/ambulance_kz_1_thumb.jpg');
      expect(photoAsset(' fire_kz_2 '), 'assets/images/fire_kz_2_thumb.jpg');
    });

    test('full size', () {
      expect(photoAsset('almaty_skyline_1', thumb: false), 'assets/images/almaty_skyline_1.jpg');
    });

    test('missing names', () {
      expect(photoAsset(null), isNull);
      expect(photoAsset(''), isNull);
      expect(photoAsset('  '), isNull);
    });
  });

  group('triage text', () {
    test('missing labels', () {
      expect(missingLabel('address'), 'адрес');
      expect(missingLabel('people_inside'), 'есть ли люди внутри');
      expect(missingLabel('victims_count'), 'сколько пострадавших');
      expect(missingLabel('patient_condition'), 'состояние пострадавшего');
      expect(missingLabel('what_happened'), 'что произошло');
      expect(missingLabel('something_new'), 'something_new');
    });

    test('priority labels', () {
      expect(priorityLabel(1), 'Экстренный');
      expect(priorityLabel(2), 'Срочный');
      expect(priorityLabel(3), 'Обычный');
      expect(priorityLabel(4), 'Плановый');
      expect(priorityLabel(null), 'Обычный');
      expect(priorityLabel(9), 'Обычный');
    });
  });
}
