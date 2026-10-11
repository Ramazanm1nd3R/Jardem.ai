/// Road closure reporting.
library;

import 'package:jardem_core/jardem_core.dart';

const List<String> kClosureReasons = ['ДТП', 'Ремонт', 'Затор', 'Другое'];

/// How long a reported closure lives unless lifted.
const int kClosureMinutes = 30;

/// List title of a closure; the reason may be empty.
String closureTitle(RoadClosure c) => c.reason.trim().isEmpty ? 'Перекрытие' : c.reason.trim();

/// Only closures reported from this device may be lifted here.
bool canLift(RoadClosure c, Set<String> mine) => mine.contains(c.id);

/// Adds / removes an id, returning a new set.
Set<String> withClosure(Set<String> mine, String id) => id.isEmpty ? mine : {...mine, id};
Set<String> withoutClosure(Set<String> mine, String id) => {...mine}..remove(id);

/// Forgets ids the server no longer lists (expired or lifted elsewhere).
Set<String> pruneClosures(Set<String> mine, List<RoadClosure> active) {
  final ids = {for (final c in active) c.id};
  return mine.intersection(ids);
}
