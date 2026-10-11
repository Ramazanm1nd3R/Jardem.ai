/// The crew's status state machine: which button(s) to show for a unit status.
library;

import 'package:jardem_core/jardem_core.dart';

/// One thing the crew can confirm with the primary button.
enum CrewStep {
  goOnDuty,
  endShift,
  accept,
  arrive,
  transport,
  complete;

  /// The `/responder/action` verb, or null for the shift toggles.
  ResponderAction? get action => switch (this) {
    CrewStep.accept => ResponderAction.accept,
    CrewStep.arrive => ResponderAction.arrive,
    CrewStep.transport => ResponderAction.transport,
    CrewStep.complete => ResponderAction.complete,
    CrewStep.goOnDuty || CrewStep.endShift => null,
  };

  /// Value for `/responder/shift`, or null for incident actions.
  bool? get onDuty => switch (this) {
    CrewStep.goOnDuty => true,
    CrewStep.endShift => false,
    _ => null,
  };
}

/// Only ambulances carry someone away from the scene.
bool hasTransportStep(ServiceType service) => service == ServiceType.ambulance;

/// Buttons for [status], most important first. Empty when nothing can be done.
///
/// off duty → go on duty; free → end shift; assigned → accept; en route →
/// confirm arrival; on scene → (ambulance: patient loaded,) complete;
/// transporting → complete.
List<CrewStep> nextSteps(UnitStatus status, ServiceType service) => switch (status) {
  UnitStatus.offDuty => const [CrewStep.goOnDuty],
  UnitStatus.available || UnitStatus.returning => const [CrewStep.endShift],
  UnitStatus.assigned => const [CrewStep.accept],
  UnitStatus.enRoute => const [CrewStep.arrive],
  UnitStatus.onScene =>
    hasTransportStep(service) ? const [CrewStep.transport, CrewStep.complete] : const [CrewStep.complete],
  UnitStatus.transporting => const [CrewStep.complete],
  UnitStatus.unknown => const [],
};

/// Ending the shift is a quiet, secondary button; everything else is primary.
bool isPrimaryStep(CrewStep step) => step != CrewStep.endShift;

/// Button label. Only the ambulance talks about a patient.
String stepLabel(CrewStep step, ServiceType service) => switch (step) {
  CrewStep.goOnDuty => 'Выйти на смену',
  CrewStep.endShift => 'Завершить смену',
  CrewStep.accept => 'Принять вызов',
  CrewStep.arrive => 'Подтвердить прибытие',
  CrewStep.transport => hasTransportStep(service) ? 'Пациент загружен' : 'Начать транспортировку',
  CrewStep.complete => 'Завершить вызов',
};

/// What a 409 on [step] means, in the crew's words.
String conflictMessage(CrewStep step) => switch (step) {
  CrewStep.goOnDuty => 'Смена уже открыта.',
  CrewStep.endShift => 'Нельзя завершить смену, пока есть активный вызов.',
  CrewStep.accept => 'Вызов уже принят или снят диспетчером.',
  CrewStep.arrive => 'Подтвердить прибытие можно только после принятия вызова.',
  CrewStep.transport => 'Отметить погрузку можно только на месте вызова.',
  CrewStep.complete => 'Завершить вызов можно после прибытия на место.',
};

/// Snackbar text for a failed [step].
String stepErrorMessage(Object error, CrewStep step) =>
    error is ApiException && error.isConflict ? conflictMessage(step) : errorMessage(error);

/// Headline of the «Текущий статус» card.
String statusTitle(UnitStatus status) => switch (status) {
  UnitStatus.offDuty => 'Не на смене',
  UnitStatus.available => 'Свободен',
  UnitStatus.assigned => 'Новый вызов',
  UnitStatus.enRoute => 'В пути',
  UnitStatus.onScene => 'На месте',
  UnitStatus.transporting => 'Транспортировка',
  UnitStatus.returning => 'Возвращение на базу',
  UnitStatus.unknown => 'Статус неизвестен',
};

/// Header chip: «На смене» / «Не на смене».
String dutyLabel(UnitStatus status) =>
    status == UnitStatus.offDuty || status == UnitStatus.unknown ? 'Не на смене' : 'На смене';

/// Vehicle card chip: «Готова» only when the crew can take a call.
String readinessLabel(UnitStatus status) => switch (status) {
  UnitStatus.available || UnitStatus.returning => 'Готова',
  UnitStatus.offDuty || UnitStatus.unknown => 'Не на смене',
  _ => 'На вызове',
};

/// «Бригада СМП №7» for an ambulance, «Экипаж …» for the other services.
String crewTitle(ServiceType service, String callsign) =>
    '${service == ServiceType.ambulance ? 'Бригада' : 'Экипаж'} $callsign'.trim();
