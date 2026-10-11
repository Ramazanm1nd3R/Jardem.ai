/// Wire enums with Russian labels.
library;

enum ServiceType {
  ambulance('ambulance', 'Скорая помощь', 'Скорая', '103', 'Вызвать скорую', 'Вызов скорой помощи'),
  police('police', 'Полиция', 'Полиция', '102', 'Вызвать полицию', 'Вызов полиции'),
  fire('fire', 'Пожарные', 'Пожарные', '101', 'Вызвать пожарных', 'Вызов пожарных'),
  rescue('rescue', 'Спасатели', 'Спасатели', '112', 'Вызвать спасателей', 'Вызов спасателей');

  const ServiceType(this.id, this.title, this.shortTitle, this.phone, this.callLabel, this.formTitle);

  final String id;
  final String title;
  final String shortTitle;

  /// Real direct number of the service in Kazakhstan.
  final String phone;
  final String callLabel;
  final String formTitle;

  static ServiceType? tryParse(Object? raw) {
    for (final s in values) {
      if (s.id == raw) return s;
    }
    return null;
  }

  /// Unknown services fall back to [rescue] (the universal 112 line).
  static ServiceType parse(Object? raw) => tryParse(raw) ?? ServiceType.rescue;
}

enum UnitStatus {
  offDuty('off_duty', 'Не на смене'),
  available('available', 'Свободен'),
  assigned('assigned', 'Назначен'),
  enRoute('en_route', 'В пути'),
  onScene('on_scene', 'На месте'),
  transporting('transporting', 'Транспортировка'),
  returning('returning', 'Возвращается'),
  unknown('unknown', 'Неизвестно');

  const UnitStatus(this.id, this.label);

  final String id;
  final String label;

  bool get isFree => this == UnitStatus.available;

  /// Short chip label used in citizen lists: «Свободен» / «Занят».
  String get chipLabel => switch (this) {
    UnitStatus.available => 'Свободен',
    UnitStatus.offDuty => 'Не на смене',
    _ => 'Занят',
  };

  static UnitStatus parse(Object? raw) {
    for (final s in values) {
      if (s.id == raw) return s;
    }
    return UnitStatus.unknown;
  }
}

enum IncidentStatus {
  created('new', 'Принят'),
  assigned('assigned', 'Экипаж назначен'),
  enRoute('en_route', 'В пути'),
  onScene('on_scene', 'На месте'),
  resolved('resolved', 'Завершён'),
  cancelled('cancelled', 'Отменён'),
  unknown('unknown', 'Неизвестно');

  const IncidentStatus(this.id, this.label);

  final String id;
  final String label;

  bool get isActive => this == created || this == assigned || this == enRoute || this == onScene;
  bool get isClosed => this == resolved || this == cancelled;

  /// The citizen may cancel until a crew has arrived.
  bool get canCancel => this == created || this == assigned || this == enRoute;

  static IncidentStatus parse(Object? raw) {
    for (final s in values) {
      if (s.id == raw) return s;
    }
    return IncidentStatus.unknown;
  }
}

enum ResponderAction {
  accept('accept'),
  arrive('arrive'),
  transport('transport'),
  complete('complete');

  const ResponderAction(this.id);
  final String id;
}
