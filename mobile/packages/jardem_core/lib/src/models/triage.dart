import 'enums.dart';
import 'json.dart';

/// Output of the rule-based text triage (`POST /triage`).
class TriageResult {
  const TriageResult({
    this.service,
    this.category,
    this.categoryTitle,
    this.priority = 3,
    this.confidence = 0,
    this.lifeThreat = false,
    this.peopleInside = false,
    this.victims,
    this.age,
    this.address,
    this.uncertain = false,
    this.matched = const [],
    this.missing = const [],
    this.also = const [],
  });

  factory TriageResult.fromJson(Json j) => TriageResult(
    service: ServiceType.tryParse(j['service']),
    category: strOrNull(j, 'category'),
    categoryTitle: strOrNull(j, 'category_title'),
    priority: integer(j, 'priority', 3),
    confidence: dbl(j, 'confidence'),
    lifeThreat: boolean(j, 'life_threat'),
    peopleInside: boolean(j, 'people_inside'),
    victims: intOrNull(j, 'victims'),
    age: intOrNull(j, 'age'),
    address: strOrNull(j, 'address'),
    uncertain: boolean(j, 'uncertain'),
    matched: strings(j['matched']),
    missing: strings(j['missing']),
    also: strings(j['also']),
  );

  final ServiceType? service;
  final String? category;
  final String? categoryTitle;
  final int priority;
  final double confidence;
  final bool lifeThreat;
  final bool peopleInside;
  final int? victims;
  final int? age;
  final String? address;

  /// True when the text did not clearly match any category.
  final bool uncertain;
  final List<String> matched;

  /// Facts a dispatcher still needs (`address`, `people_inside` …).
  final List<String> missing;
  final List<String> also;

  bool get hasSuggestion => service != null && category != null && !uncertain;
}
