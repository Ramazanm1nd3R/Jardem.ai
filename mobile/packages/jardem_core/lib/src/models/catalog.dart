import 'enums.dart';
import 'json.dart';

/// A call category inside a service («Экстренная помощь», «Патруль» …).
class Category {
  const Category({
    required this.id,
    required this.title,
    this.description = '',
    this.priority = 3,
    this.unitsRequired = 1,
  });

  factory Category.fromJson(Json j) => Category(
    id: str(j, 'id'),
    title: str(j, 'title'),
    description: str(j, 'description'),
    priority: integer(j, 'priority', 3),
    unitsRequired: integer(j, 'units_required', 1),
  );

  final String id;
  final String title;
  final String description;
  final int priority;
  final int unitsRequired;

  /// Chip label: drops a trailing « помощь» so «Экстренная помощь» fits a chip.
  String get shortTitle => title.endsWith(' помощь') ? title.substring(0, title.length - 7) : title;
}

/// One of the four services with its categories.
class ServiceInfo {
  const ServiceInfo({required this.service, required this.title, required this.phone, this.categories = const []});

  factory ServiceInfo.fromJson(Json j) {
    final service = ServiceType.parse(j['id']);
    return ServiceInfo(
      service: service,
      title: str(j, 'title', service.title),
      phone: str(j, 'phone', service.phone),
      categories: listOf(j['categories'], Category.fromJson),
    );
  }

  static List<ServiceInfo> listFromJson(Object? raw) => listOf(raw, ServiceInfo.fromJson);

  final ServiceType service;
  final String title;
  final String phone;
  final List<Category> categories;

  String get id => service.id;

  Category? category(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Finds the service that owns [categoryId] in a catalog.
ServiceInfo? serviceOfCategory(List<ServiceInfo> catalog, String? categoryId) {
  for (final s in catalog) {
    if (s.category(categoryId) != null) return s;
  }
  return null;
}
