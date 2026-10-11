import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/timeline.dart';

final _start = DateTime.utc(2025, 4, 15, 3);
final _accepted = DateTime.utc(2025, 4, 15, 7, 24);
final _arrived = DateTime.utc(2025, 4, 15, 7, 31);
final _loaded = DateTime.utc(2025, 4, 15, 7, 40);

Incident _incident({bool enRoute = true, bool onScene = false, int? eta = 240, int? dist = 1200}) => Incident(
  id: 'inc-1',
  number: 45821,
  service: ServiceType.ambulance,
  timeline: [
    TimelineEntry(status: 'new', at: DateTime.utc(2025, 4, 15, 7, 20)),
    TimelineEntry(status: 'assigned', at: DateTime.utc(2025, 4, 15, 7, 21)),
    if (enRoute) TimelineEntry(status: 'en_route', at: _accepted),
    if (onScene) TimelineEntry(status: 'on_scene', at: _arrived),
  ],
  my: MyAssignment(etaS: eta, distanceM: dist),
);

List<ShiftStep> _build(
  UnitStatus status, {
  ServiceType service = ServiceType.ambulance,
  Incident? incident,
  DateTime? transportAt,
}) => buildShiftTimeline(
  status: status,
  service: service,
  shiftStartedAt: _start,
  assignment: incident,
  transportAt: transportAt,
);

void main() {
  test('current step per status', () {
    expect(currentShiftStep(UnitStatus.offDuty), -1);
    expect(currentShiftStep(UnitStatus.unknown), -1);
    expect(currentShiftStep(UnitStatus.available), 0);
    expect(currentShiftStep(UnitStatus.returning), 0);
    expect(currentShiftStep(UnitStatus.assigned), 0);
    expect(currentShiftStep(UnitStatus.enRoute), 2);
    expect(currentShiftStep(UnitStatus.onScene), 3);
    expect(currentShiftStep(UnitStatus.transporting), 4);
  });

  test('ambulance has six steps in the mock-up order', () {
    final steps = _build(UnitStatus.available);
    expect(steps.map((s) => s.id), ['duty', 'accepted', 'en_route', 'on_scene', 'transport', 'done']);
    expect(steps.map((s) => s.title), [
      'На смене',
      'Вызов принят',
      'В пути',
      'На месте',
      'Пациент загружен',
      'Инцидент отработан',
    ]);
  });

  test('other services have no transport step', () {
    for (final s in [ServiceType.fire, ServiceType.police, ServiceType.rescue]) {
      final steps = _build(UnitStatus.onScene, service: s, incident: _incident(onScene: true));
      expect(steps.map((e) => e.id), ['duty', 'accepted', 'en_route', 'on_scene', 'done'], reason: s.id);
      expect(steps.map((e) => e.phase), [
        StepPhase.done,
        StepPhase.done,
        StepPhase.done,
        StepPhase.active,
        StepPhase.pending,
      ]);
    }
  });

  test('off duty: everything pending, no times', () {
    final steps = _build(UnitStatus.offDuty);
    expect(steps.every((s) => s.phase == StepPhase.pending), isTrue);
    expect(steps.every((s) => s.at == null), isTrue);
    expect(steps.first.subtitle, 'Смена не начата');
    expect(_build(UnitStatus.unknown).first.subtitle, 'Смена не начата');
    expect(steps[1].subtitle, 'Подтвердите приём вызова');
  });

  test('available: on shift is the active step with the shift start time', () {
    final steps = _build(UnitStatus.available);
    expect(steps.first.phase, StepPhase.active);
    expect(steps.first.at, _start);
    expect(steps.first.subtitle, 'Готов к вызовам');
    expect(steps.skip(1).every((s) => s.phase == StepPhase.pending), isTrue);
    expect(_build(UnitStatus.returning).first.subtitle, 'Возвращение на базу');
    expect(_build(UnitStatus.returning).first.phase, StepPhase.active);
  });

  test('assigned: waits for acceptance', () {
    final steps = _build(UnitStatus.assigned, incident: _incident(enRoute: false));
    expect(steps[0].phase, StepPhase.active);
    expect(steps[0].subtitle, 'Новый вызов #45821 ждёт подтверждения');
    expect(steps[1].phase, StepPhase.pending);
    expect(steps[1].subtitle, 'Подтвердите приём вызова');
    expect(steps[1].at, isNull);
    expect(steps[2].subtitle, 'Движение к месту вызова');
    expect(steps[3].subtitle, 'Подтвердите прибытие');
  });

  test('en route: accepted is done with its time, «В пути» shows distance and ETA', () {
    final steps = _build(UnitStatus.enRoute, incident: _incident());
    expect(steps.map((s) => s.phase), [
      StepPhase.done,
      StepPhase.done,
      StepPhase.active,
      StepPhase.pending,
      StepPhase.pending,
      StepPhase.pending,
    ]);
    expect(steps[0].subtitle, 'Готов к вызовам');
    expect(steps[0].at, _start);
    expect(steps[1].subtitle, '#45821');
    expect(steps[1].at, _accepted);
    expect(steps[2].subtitle, '1,2 км · 4 мин');
    expect(steps[2].at, _accepted);
    expect(steps[3].at, isNull);
    expect(steps[3].subtitle, 'Подтвердите прибытие');
    expect(steps[4].subtitle, 'Начало транспортировки');
    expect(steps[5].subtitle, 'Завершение вызова');
  });

  test('en route without a route yet', () {
    final steps = _build(UnitStatus.enRoute, incident: _incident(eta: null, dist: null));
    expect(steps[2].subtitle, 'Маршрут уточняется');
  });

  test('on scene: arrival time, transport still pending without a time', () {
    final steps = _build(UnitStatus.onScene, incident: _incident(onScene: true), transportAt: _loaded);
    expect(steps[2].phase, StepPhase.done);
    expect(steps[2].subtitle, 'Движение к месту вызова');
    expect(steps[3].phase, StepPhase.active);
    expect(steps[3].at, _arrived);
    expect(steps[3].subtitle, 'Прибытие подтверждено');
    // The accepted step keeps the call number after «В пути».
    expect(steps[1].subtitle, '#45821');
    expect(steps[1].at, _accepted);
    expect(steps[4].phase, StepPhase.pending);
    expect(steps[4].at, isNull);
  });

  test('transporting: the transport step is active with the confirmation time', () {
    final steps = _build(UnitStatus.transporting, incident: _incident(onScene: true), transportAt: _loaded);
    expect(steps[3].phase, StepPhase.done);
    expect(steps[3].subtitle, 'Прибытие подтверждено');
    expect(steps[1].subtitle, '#45821');
    expect(steps[4].phase, StepPhase.active);
    expect(steps[4].at, _loaded);
    expect(steps[5].phase, StepPhase.pending);
    expect(steps[5].at, isNull);
  });
}
