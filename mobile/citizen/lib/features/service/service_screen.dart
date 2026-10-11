import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/dial.dart';
import '../../shared/widgets.dart';
import '../../state/location.dart';
import '../../state/providers.dart';
import '../../state/units.dart';

/// How many crews a service listing asks for.
const int kServiceUnitsLimit = 12;

UnitsQuery serviceUnitsQuery(ServiceType service, String? category, UserLocation location) =>
    UnitsQuery(service: service, category: category, near: location.point, limit: kServiceUnitsLimit);

/// First free unit of a list sorted «free first, then by ETA».
Unit? nearestFree(List<Unit> units) {
  for (final u in units) {
    if (u.free) return u;
  }
  return null;
}

/// «Скорая помощь • Экстренная».
String unitSubtitle(ServiceInfo? info, ServiceType service, Category? category) =>
    [info?.title ?? service.title, if (category != null) category.shortTitle].join(' • ');

/// Per-service map: category chips, that service's crews, the nearest free
/// one highlighted with a dashed route, and the «Вызвать» card.
class ServiceScreen extends ConsumerStatefulWidget {
  const ServiceScreen({super.key, required this.service, this.initialCategory});

  final ServiceType service;
  final String? initialCategory;

  @override
  ConsumerState<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends ConsumerState<ServiceScreen> {
  final _map = MapController();
  late String? _category = widget.initialCategory;
  bool _mapReady = false;

  @override
  void didUpdateWidget(ServiceScreen old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service || old.initialCategory != widget.initialCategory) {
      _category = widget.initialCategory;
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _frame(Unit? unit, UserLocation location) {
    if (!_mapReady) return;
    final fit = JardemMap.fitFor([
      location.point,
      if (unit != null) unit.position,
      ...?unit?.route,
    ], const EdgeInsets.fromLTRB(56, 176, 56, 64));
    if (fit != null) {
      _map.fitCamera(fit);
    } else {
      _map.move(location.point, 14);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final color = JardemColors.service(service);
    final location = ref.watch(locationProvider);
    final catalog = ref.watch(catalogProvider);
    final info = catalog.valueOrNull?.where((s) => s.service == service).firstOrNull;
    final categories = info?.categories ?? const <Category>[];
    final category = info?.category(_category) ?? categories.firstOrNull;
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();

    // Wait for the catalog so the first units request already has a category.
    final query = serviceUnitsQuery(service, category?.id, location);
    final units = catalog.isLoading ? const AsyncValue<List<Unit>>.loading() : ref.watch(unitsProvider(query));
    final list = units.valueOrNull ?? const <Unit>[];
    final nearest = nearestFree(list);
    final routeKey = nearest == null ? null : (unitId: nearest.id, to: location.point);
    final routed = routeKey == null ? null : ref.watch(unitRouteProvider(routeKey)).valueOrNull;

    // Re-frame the map when the highlighted unit (or its route) changes.
    ref.listen(unitsProvider(query).select((v) => nearestFree(v.valueOrNull ?? const [])?.id), (prev, next) {
      if (prev != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _frame(nearestFree(ref.read(unitsProvider(query)).valueOrNull ?? const []), location);
          }
        });
      }
    });

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: JardemMap(
                  controller: _map,
                  center: location.point,
                  zoom: 13.8,
                  units: [for (final u in list) MapUnit.of(u, highlighted: u.id == nearest?.id, dimBusy: true)],
                  myLocation: location.point,
                  routes: [
                    if (routed != null && routed.route.length > 1)
                      MapRoute(points: routed.route, color: color, dashed: true, width: 3),
                  ],
                  onMapReady: () {
                    _mapReady = true;
                    _frame(nearest, location);
                  },
                  attributionPadding: const EdgeInsets.only(left: 8, bottom: 8),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: _ServiceHeader(
                        service: service,
                        title: info?.title ?? service.title,
                        onCategories: () async {
                          final picked = await context.push<String>('/service/${service.id}/categories');
                          if (picked != null && mounted) setState(() => _category = picked);
                        },
                      ),
                    ),
                    if (categories.isNotEmpty)
                      PillChips<Category>(
                        items: categories,
                        selected: category,
                        labelOf: (c) => c.shortTitle,
                        color: color,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onSelected: (c) => setState(() => _category = c.id),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: SquareIconButton(
                  icon: Icons.near_me_rounded,
                  color: JardemColors.primary,
                  tooltip: 'Показать меня и экипаж',
                  onPressed: () => _frame(routed ?? nearest, location),
                ),
              ),
            ],
          ),
        ),
        _BottomCard(
          service: service,
          phone: info?.phone ?? meta.phoneOf(service),
          units: units,
          catalogError: catalog.hasError ? catalog.error : null,
          nearest: nearest == null ? null : (routed ?? nearest),
          subtitle: unitSubtitle(info, service, category),
          onRetry: () {
            if (catalog.hasError) ref.invalidate(catalogProvider);
            if (!catalog.isLoading) ref.read(unitsProvider(query).notifier).refresh();
          },
          onUnits: () => context.push(
            Uri(path: '/service/${service.id}/units', queryParameters: {'category': ?category?.id}).toString(),
          ),
          onCall: () =>
              context.push(Uri(path: '/call/${service.id}', queryParameters: {'category': ?category?.id}).toString()),
          onDial: (number) => dial(context, ref, number),
        ),
      ],
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({required this.service, required this.title, required this.onCategories});

  final ServiceType service;
  final String title;
  final VoidCallback onCategories;

  @override
  Widget build(BuildContext context) => JardemCard(
    radius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => context.go('/map'),
        ),
        Expanded(
          child: PopupMenuButton<ServiceType>(
            tooltip: 'Сменить службу',
            position: PopupMenuPosition.under,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (s) => context.go('/map/service/${s.id}'),
            itemBuilder: (_) => [
              for (final s in ServiceType.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      ServiceBadge(s, size: 26),
                      const SizedBox(width: 10),
                      Text(s.title, style: JardemTheme.text(14, FontWeight.w700)),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  ServiceBadge(service, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JardemTheme.text(16, FontWeight.w800),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, color: JardemColors.navy),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Категории',
          icon: const Icon(Icons.format_list_bulleted_rounded, size: 22, color: JardemColors.muted),
          onPressed: onCategories,
        ),
      ],
    ),
  );
}

class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.service,
    required this.phone,
    required this.units,
    required this.catalogError,
    required this.nearest,
    required this.subtitle,
    required this.onRetry,
    required this.onUnits,
    required this.onCall,
    required this.onDial,
  });

  final ServiceType service;
  final String phone;
  final AsyncValue<List<Unit>> units;
  final Object? catalogError;
  final Unit? nearest;
  final String subtitle;
  final VoidCallback onRetry;
  final VoidCallback onUnits;
  final VoidCallback onCall;
  final ValueChanged<String> onDial;

  @override
  Widget build(BuildContext context) {
    final error = catalogError ?? (units.hasValue ? null : units.error);
    final Widget top;
    if (error != null) {
      top = MessageView.error(error, onRetry: onRetry, compact: true);
    } else if (!units.hasValue) {
      top = const SizedBox(height: 62, child: LoadingView(label: 'Ищем ближайший экипаж…'));
    } else if (nearest != null) {
      top = UnitCard(
        unit: nearest!,
        subtitle: subtitle,
        flat: true,
        onTap: onUnits,
        trailing: const Icon(Icons.chevron_right_rounded, color: JardemColors.faint),
      );
    } else {
      top = MessageView(
        icon: Icons.hourglass_empty_rounded,
        title: units.value!.isEmpty ? 'Нет экипажей на смене' : 'Все экипажи заняты',
        text: 'Вызов можно оставить — он будет назначен первому освободившемуся экипажу.',
        actionLabel: units.value!.isEmpty ? null : 'Показать экипажи',
        onAction: onUnits,
        compact: true,
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Color(0x1F1A4B8C), blurRadius: 24, offset: Offset(0, -6))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          top,
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  key: const Key('service-call'),
                  label: 'Вызвать',
                  height: 48,
                  radius: 14,
                  onPressed: onCall,
                ),
              ),
              const SizedBox(width: 10),
              SquareIconButton(
                icon: Icons.phone_rounded,
                color: JardemColors.primary,
                bordered: true,
                tooltip: 'Позвонить $phone',
                onPressed: () => onDial(phone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
