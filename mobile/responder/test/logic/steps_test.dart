import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/steps.dart';

void main() {
  group('CrewStep', () {
    test('maps to API verbs', () {
      expect(CrewStep.accept.action, ResponderAction.accept);
      expect(CrewStep.arrive.action, ResponderAction.arrive);
      expect(CrewStep.transport.action, ResponderAction.transport);
      expect(CrewStep.complete.action, ResponderAction.complete);
      expect(CrewStep.goOnDuty.action, isNull);
      expect(CrewStep.endShift.action, isNull);
    });

    test('shift toggles carry the on_duty value', () {
      expect(CrewStep.goOnDuty.onDuty, isTrue);
      expect(CrewStep.endShift.onDuty, isFalse);
      for (final s in [CrewStep.accept, CrewStep.arrive, CrewStep.transport, CrewStep.complete]) {
        expect(s.onDuty, isNull, reason: s.name);
      }
    });
  });

  test('only ambulances transport', () {
    expect(hasTransportStep(ServiceType.ambulance), isTrue);
    expect(hasTransportStep(ServiceType.fire), isFalse);
    expect(hasTransportStep(ServiceType.police), isFalse);
    expect(hasTransportStep(ServiceType.rescue), isFalse);
  });

  group('nextSteps', () {
    test('ambulance state machine', () {
      const s = ServiceType.ambulance;
      expect(nextSteps(UnitStatus.offDuty, s), [CrewStep.goOnDuty]);
      expect(nextSteps(UnitStatus.available, s), [CrewStep.endShift]);
      expect(nextSteps(UnitStatus.returning, s), [CrewStep.endShift]);
      expect(nextSteps(UnitStatus.assigned, s), [CrewStep.accept]);
      expect(nextSteps(UnitStatus.enRoute, s), [CrewStep.arrive]);
      expect(nextSteps(UnitStatus.onScene, s), [CrewStep.transport, CrewStep.complete]);
      expect(nextSteps(UnitStatus.transporting, s), [CrewStep.complete]);
      expect(nextSteps(UnitStatus.unknown, s), isEmpty);
    });

    test('other services skip the transport step', () {
      for (final s in [ServiceType.fire, ServiceType.police, ServiceType.rescue]) {
        expect(nextSteps(UnitStatus.onScene, s), [CrewStep.complete], reason: s.id);
        expect(nextSteps(UnitStatus.enRoute, s), [CrewStep.arrive]);
        expect(nextSteps(UnitStatus.assigned, s), [CrewStep.accept]);
        for (final status in UnitStatus.values) {
          expect(nextSteps(status, s), isNot(contains(CrewStep.transport)));
        }
      }
    });
  });

  test('only ending the shift is secondary', () {
    for (final s in CrewStep.values) {
      expect(isPrimaryStep(s), s != CrewStep.endShift, reason: s.name);
    }
  });

  test('labels', () {
    const a = ServiceType.ambulance;
    expect(stepLabel(CrewStep.goOnDuty, a), 'Выйти на смену');
    expect(stepLabel(CrewStep.endShift, a), 'Завершить смену');
    expect(stepLabel(CrewStep.accept, a), 'Принять вызов');
    expect(stepLabel(CrewStep.arrive, a), 'Подтвердить прибытие');
    expect(stepLabel(CrewStep.transport, a), 'Пациент загружен');
    expect(stepLabel(CrewStep.complete, a), 'Завершить вызов');
    expect(stepLabel(CrewStep.transport, ServiceType.fire), 'Начать транспортировку');
    expect(stepLabel(CrewStep.complete, ServiceType.police), 'Завершить вызов');
  });

  test('conflict explanations are specific', () {
    expect(conflictMessage(CrewStep.goOnDuty), 'Смена уже открыта.');
    expect(conflictMessage(CrewStep.endShift), 'Нельзя завершить смену, пока есть активный вызов.');
    expect(conflictMessage(CrewStep.accept), 'Вызов уже принят или снят диспетчером.');
    expect(conflictMessage(CrewStep.arrive), 'Подтвердить прибытие можно только после принятия вызова.');
    expect(conflictMessage(CrewStep.transport), 'Отметить погрузку можно только на месте вызова.');
    expect(conflictMessage(CrewStep.complete), 'Завершить вызов можно после прибытия на место.');
  });

  test('stepErrorMessage: 409 explains, everything else is generic', () {
    expect(stepErrorMessage(const ApiException(409, 'x'), CrewStep.arrive), conflictMessage(CrewStep.arrive));
    expect(stepErrorMessage(const ApiException.network(), CrewStep.arrive), const ApiException.network().userMessage);
    expect(stepErrorMessage(const ApiException(500, 'x'), CrewStep.accept), const ApiException(500, '').userMessage);
    expect(stepErrorMessage(StateError('x'), CrewStep.accept), 'Что-то пошло не так. Попробуйте ещё раз.');
  });

  test('status titles', () {
    expect(statusTitle(UnitStatus.offDuty), 'Не на смене');
    expect(statusTitle(UnitStatus.available), 'Свободен');
    expect(statusTitle(UnitStatus.assigned), 'Новый вызов');
    expect(statusTitle(UnitStatus.enRoute), 'В пути');
    expect(statusTitle(UnitStatus.onScene), 'На месте');
    expect(statusTitle(UnitStatus.transporting), 'Транспортировка');
    expect(statusTitle(UnitStatus.returning), 'Возвращение на базу');
    expect(statusTitle(UnitStatus.unknown), 'Статус неизвестен');
  });

  test('duty chip', () {
    expect(dutyLabel(UnitStatus.offDuty), 'Не на смене');
    expect(dutyLabel(UnitStatus.unknown), 'Не на смене');
    for (final s in UnitStatus.values.where((s) => s != UnitStatus.offDuty && s != UnitStatus.unknown)) {
      expect(dutyLabel(s), 'На смене', reason: s.id);
    }
  });

  test('vehicle readiness', () {
    expect(readinessLabel(UnitStatus.available), 'Готова');
    expect(readinessLabel(UnitStatus.returning), 'Готова');
    expect(readinessLabel(UnitStatus.offDuty), 'Не на смене');
    expect(readinessLabel(UnitStatus.unknown), 'Не на смене');
    expect(readinessLabel(UnitStatus.assigned), 'На вызове');
    expect(readinessLabel(UnitStatus.enRoute), 'На вызове');
    expect(readinessLabel(UnitStatus.onScene), 'На вызове');
    expect(readinessLabel(UnitStatus.transporting), 'На вызове');
  });

  test('crew title', () {
    expect(crewTitle(ServiceType.ambulance, 'СМП №7'), 'Бригада СМП №7');
    expect(crewTitle(ServiceType.fire, 'ПЧ №9'), 'Экипаж ПЧ №9');
    expect(crewTitle(ServiceType.police, ''), 'Экипаж');
  });
}
