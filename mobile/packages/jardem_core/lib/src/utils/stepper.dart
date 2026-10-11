/// Incident status → the citizen's 4-step progress indicator.
library;

import '../models/enums.dart';

enum StepPhase { done, active, pending }

const List<String> kCitizenSteps = ['Принят', 'Экипаж выехал', 'В пути', 'Прибытие'];

/// States of «Принят → Экипаж выехал → В пути → Прибытие» for [status].
///
/// * new / assigned ⇒ step 0 done
/// * en_route ⇒ steps 0–1 done, «В пути» active
/// * on_scene / resolved ⇒ all done
/// * cancelled / unknown ⇒ only the first step done
List<StepPhase> citizenStepper(IncidentStatus status) {
  final done = switch (status) {
    IncidentStatus.enRoute => 2,
    IncidentStatus.onScene || IncidentStatus.resolved => 4,
    _ => 1,
  };
  final active = status == IncidentStatus.enRoute ? 2 : -1;
  return [
    for (var i = 0; i < kCitizenSteps.length; i++)
      i < done ? StepPhase.done : (i == active ? StepPhase.active : StepPhase.pending),
  ];
}

/// Headline shown above the stepper on the tracking screen.
String citizenStatusTitle(IncidentStatus status) => switch (status) {
  IncidentStatus.created => 'Вызов принят',
  IncidentStatus.assigned => 'Экипаж назначен',
  IncidentStatus.enRoute => 'Экипаж в пути',
  IncidentStatus.onScene => 'Экипаж на месте',
  IncidentStatus.resolved => 'Вызов завершён',
  IncidentStatus.cancelled => 'Вызов отменён',
  IncidentStatus.unknown => 'Вызов принят',
};

/// Seconds from call creation to first arrival; prefers the server's value.
int? timeToArrivalS({int? firstArrivalS, DateTime? createdAt, DateTime? arrivedAt}) {
  if (firstArrivalS != null) return firstArrivalS;
  if (createdAt == null || arrivedAt == null) return null;
  final s = arrivedAt.difference(createdAt).inSeconds;
  return s < 0 ? null : s;
}
