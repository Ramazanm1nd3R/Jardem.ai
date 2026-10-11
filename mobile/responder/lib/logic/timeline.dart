/// The vertical «Смена и статус» timeline.
library;

import 'package:jardem_core/jardem_core.dart';

import 'steps.dart';

class ShiftStep {
  const ShiftStep({required this.id, required this.title, this.subtitle = '', this.at, required this.phase});

  /// duty / accepted / en_route / on_scene / transport / done.
  final String id;
  final String title;
  final String subtitle;

  /// When the step happened, if known.
  final DateTime? at;
  final StepPhase phase;
}

/// Index of the step the crew is in right now; -1 when off duty.
int currentShiftStep(UnitStatus status) => switch (status) {
  UnitStatus.offDuty || UnitStatus.unknown => -1,
  UnitStatus.available || UnitStatus.returning || UnitStatus.assigned => 0,
  UnitStatus.enRoute => 2,
  UnitStatus.onScene => 3,
  UnitStatus.transporting => 4,
};

/// На смене → Вызов принят → В пути → На месте → (Пациент загружен) →
/// Инцидент отработан. Steps before the current one are done, later ones
/// pending. The transport step exists only for ambulances.
List<ShiftStep> buildShiftTimeline({
  required UnitStatus status,
  required ServiceType service,
  DateTime? shiftStartedAt,
  Incident? assignment,
  DateTime? transportAt,
}) {
  final current = currentShiftStep(status);
  final number = assignment == null ? '' : '#${assignment.number}';
  final accepted = assignment?.reachedAt(IncidentStatus.enRoute);
  final my = assignment?.my;
  final steps = <ShiftStep>[];

  void add(int index, String id, String title, String subtitle, DateTime? at) {
    final phase = index < current ? StepPhase.done : (index == current ? StepPhase.active : StepPhase.pending);
    steps.add(
      ShiftStep(id: id, title: title, subtitle: subtitle, at: phase == StepPhase.pending ? null : at, phase: phase),
    );
  }

  add(0, 'duty', 'На смене', switch (status) {
    UnitStatus.offDuty || UnitStatus.unknown => 'Смена не начата',
    UnitStatus.assigned => 'Новый вызов $number ждёт подтверждения',
    UnitStatus.returning => 'Возвращение на базу',
    _ => 'Готов к вызовам',
  }, shiftStartedAt);
  add(1, 'accepted', 'Вызов принят', current >= 2 ? number : 'Подтвердите приём вызова', accepted);
  add(
    2,
    'en_route',
    'В пути',
    current == 2
        ? formatDistanceEta(my?.distanceM, my?.etaS, separator: ' · ').replaceAll(kNoValue, 'Маршрут уточняется')
        : 'Движение к месту вызова',
    accepted,
  );
  add(
    3,
    'on_scene',
    'На месте',
    current < 3 ? 'Подтвердите прибытие' : 'Прибытие подтверждено',
    assignment?.reachedAt(IncidentStatus.onScene),
  );
  if (hasTransportStep(service)) {
    add(4, 'transport', 'Пациент загружен', 'Начало транспортировки', transportAt);
  }
  add(5, 'done', 'Инцидент отработан', 'Завершение вызова', null);
  return steps;
}
