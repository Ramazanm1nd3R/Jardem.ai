/// Null-tolerant JSON accessors used by every model.
library;

typedef Json = Map<String, dynamic>;

Json asJson(Object? raw) => raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};

String str(Json j, String key, [String fallback = '']) {
  final v = j[key];
  return v == null ? fallback : v.toString();
}

String? strOrNull(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

double dbl(Json j, String key, [double fallback = 0]) => dblOrNull(j, key) ?? fallback;

double? dblOrNull(Json j, String key) {
  final v = j[key];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int integer(Json j, String key, [int fallback = 0]) => intOrNull(j, key) ?? fallback;

int? intOrNull(Json j, String key) {
  final v = j[key];
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

bool boolean(Json j, String key, [bool fallback = false]) {
  final v = j[key];
  return v is bool ? v : fallback;
}

DateTime? dateOrNull(Json j, String key) {
  final v = j[key];
  return v is String ? DateTime.tryParse(v) : null;
}

List<T> listOf<T>(Object? raw, T Function(Json) parse) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) parse(item.cast<String, dynamic>()),
  ];
}

List<String> strings(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final v in raw)
      if (v != null) v.toString(),
  ];
}
