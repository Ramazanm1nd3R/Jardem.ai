/// Facts shown on the call details screen.
library;

import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

class CallFact {
  const CallFact(this.label, this.value, {this.alert = false});

  final String label;
  final String value;

  /// Drawn in red (danger to life, people inside).
  final bool alert;
}

/// Triage output as label/value rows; unknown facts are left out.
List<CallFact> triageFacts(TriageResult? t) {
  if (t == null) return const [];
  return [
    CallFact('Угроза жизни', t.lifeThreat ? 'Есть' : 'Не указана', alert: t.lifeThreat),
    if (t.age != null) CallFact('Возраст', '${t.age} ${plural(t.age!, 'год', 'года', 'лет')}'),
    if (t.victims != null) CallFact('Пострадавших', '${t.victims}'),
    if (t.peopleInside) const CallFact('Люди внутри', 'Да', alert: true),
    if (t.missing.isNotEmpty) CallFact('Нужно уточнить', t.missing.map(missingLabel).join(', ')),
  ];
}

/// Priority 1 is the red «Экстренный» chip, 2 is orange, the rest are calm.
bool isCritical(int priority) => priority <= 1;
bool isUrgent(int priority) => priority == 2;

/// «Экстренный вызов», «Срочный вызов» …
String priorityCallLabel(int priority) => '${priorityLabel(priority)} вызов';

/// Address line; the API leaves it empty when the caller only dropped a pin.
String addressOrPoint(Incident i) {
  final a = i.address.trim();
  return a.isNotEmpty ? a : 'Точка на карте: ${i.lat.toStringAsFixed(4)}, ${i.lon.toStringAsFixed(4)}';
}

/// «Оборудование (6/6)» + whether everything is fine.
({String title, String status, bool ok}) equipmentSummary(List<EquipmentItem> items) {
  final good = items.where((e) => e.ok).length;
  final bad = items.length - good;
  return (
    title: 'Оборудование ($good/${items.length})',
    status: bad == 0 ? 'Все в порядке' : 'Требует проверки: $bad',
    ok: bad == 0,
  );
}

/// Link for an external navigator: `geo:` on Android, Apple Maps on iOS and a
/// Google Maps directions URL elsewhere (web).
Uri navigatorUri(LatLng to, {required bool android, required bool ios}) {
  final point = '${to.latitude},${to.longitude}';
  if (android) return Uri.parse('geo:$point?q=$point');
  if (ios) return Uri.parse('https://maps.apple.com/?daddr=$point&dirflg=d');
  return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$point&travelmode=driving');
}
