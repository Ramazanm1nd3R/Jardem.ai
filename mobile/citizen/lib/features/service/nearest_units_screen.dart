import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/widgets.dart';
import '../../state/location.dart';
import '../../state/units.dart';
import 'service_screen.dart';

/// «Ближайшие экипажи»: mini map and a list with distance, ETA and status.
class NearestUnitsScreen extends ConsumerWidget {
  const NearestUnitsScreen({super.key, required this.service, this.category});

  final ServiceType service;
  final String? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationProvider);
    final query = serviceUnitsQuery(service, category, location);
    final units = ref.watch(unitsProvider(query));
    final color = JardemColors.service(service);

    return Scaffold(
      appBar: JardemAppBar(title: 'Ближайшие экипажи', fallbackLocation: '/map/service/${service.id}'),
      body: units.when(
        loading: () => const LoadingView(),
        error: (e, _) => MessageView.error(e, onRetry: () => ref.read(unitsProvider(query).notifier).refresh()),
        data: (list) {
          if (list.isEmpty) {
            return const MessageView(
              icon: Icons.local_shipping_outlined,
              title: 'Нет экипажей на смене',
              text: 'Попробуйте другую категорию или позвоните 112.',
            );
          }
          final nearest = nearestFree(list);
          final routed = nearest == null
              ? null
              : ref.watch(unitRouteProvider((unitId: nearest.id, to: location.point))).valueOrNull;
          final shown = list.take(6).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 190,
                  child: JardemMap(
                    key: ValueKey('mini-${nearest?.id}-${shown.length}'),
                    interactive: false,
                    center: location.point,
                    fitPoints: [location.point, for (final u in shown.take(3)) u.position],
                    fitPadding: const EdgeInsets.all(40),
                    myLocation: location.point,
                    units: [for (final u in shown) MapUnit.of(u, highlighted: u.id == nearest?.id, dimBusy: true)],
                    routes: [
                      if (routed != null && routed.route.length > 1)
                        MapRoute(points: routed.route, color: color, dashed: true, width: 3),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final u in list) ...[
                UnitCard(
                  key: Key('unit-${u.id}'),
                  unit: u,
                  subtitle: u.callsign.isEmpty ? u.vehicle : '${u.callsign} · ${u.vehicle}',
                  trailing: StatusChip.unit(u.status),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}
