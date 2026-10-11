/// Dispatcher chat helpers.
library;

import 'package:jardem_core/jardem_core.dart';

import 'steps.dart';

/// One-tap answers. «Принял», «В пути», «На месте» are always there; the one
/// matching the crew's status comes first, plus a contextual extra.
List<String> quickReplies(UnitStatus status, ServiceType service) {
  const base = ['Принял', 'В пути', 'На месте'];
  final first = switch (status) {
    UnitStatus.enRoute => 'В пути',
    UnitStatus.onScene => 'На месте',
    _ => 'Принял',
  };
  final extra = switch (status) {
    UnitStatus.onScene => 'Нужна помощь',
    UnitStatus.transporting => hasTransportStep(service) ? 'Везём в стационар' : 'Освобожусь через 10 мин',
    UnitStatus.enRoute => 'Задерживаюсь',
    _ => 'Свободен',
  };
  return [first, ...base.where((r) => r != first), extra];
}

/// Text as it will be sent, or null when there is nothing to send.
String? outgoingText(String raw) {
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

/// Dispatcher messages newer than [lastReadAt] (all of them when never read).
int unreadCount(List<Message> messages, DateTime? lastReadAt) {
  var n = 0;
  for (final m in messages) {
    if (!m.fromDispatcher) continue;
    final at = m.at;
    if (lastReadAt == null || (at != null && at.isAfter(lastReadAt))) n++;
  }
  return n;
}

/// Badge text: nothing at zero, «9+» past nine.
String badgeText(int count) => count <= 0 ? '' : (count > 9 ? '9+' : '$count');
