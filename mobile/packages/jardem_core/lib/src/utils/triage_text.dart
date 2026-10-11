/// Human-readable labels for triage output.
library;

const Map<String, String> _missingLabels = {
  'address': 'адрес',
  'what_happened': 'что произошло',
  'patient_condition': 'состояние пострадавшего',
  'victims_count': 'сколько пострадавших',
  'people_inside': 'есть ли люди внутри',
};

/// Russian label of a `missing[]` key; unknown keys are shown as-is.
String missingLabel(String key) => _missingLabels[key] ?? key;

/// `Экстренный` … `Низкий` for priorities 1…4 (anything else → `Обычный`).
String priorityLabel(int? priority) => switch (priority) {
  1 => 'Экстренный',
  2 => 'Срочный',
  3 => 'Обычный',
  4 => 'Плановый',
  _ => 'Обычный',
};
