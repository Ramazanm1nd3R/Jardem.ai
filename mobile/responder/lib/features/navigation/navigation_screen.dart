import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../../logic/details.dart';
import '../../logic/eta.dart';
import '../../logic/maneuver.dart';
import '../../logic/steps.dart';
import '../../shared/step_buttons.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';
import '../../state/map.dart';
import '../../state/providers.dart';

/// «Навигация»: the map with the traffic-coloured route to the call, the next
/// maneuver on top and the ETA sheet with the status button at the bottom.
class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final _map = MapController();
  bool _follow = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _safely(void Function() move) {
    try {
      move();
    } catch (_) {
      // The map is not laid out yet (hidden tab).
    }
  }

  void _zoom(double delta) => _safely(() => _map.move(_map.camera.center, (_map.camera.zoom + delta).clamp(9, 18)));

  void _recenter(LatLng at) {
    setState(() => _follow = true);
    _safely(() => _map.move(at, _map.camera.zoom < 15 ? 16 : _map.camera.zoom));
  }

  void _overview(List<LatLng> points) {
    setState(() => _follow = false);
    final fit = JardemMap.fitFor(points, const EdgeInsets.fromLTRB(56, 150, 56, 300));
    if (fit != null) _safely(() => _map.fitCamera(fit));
  }

  Future<void> _openNavigator(LatLng to) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref.read(navigatorOpenerProvider)(to);
    if (!ok) toast(messenger, 'Не удалось открыть навигатор на этом устройстве.');
  }

  @override
  Widget build(BuildContext context) {
    final crew = ref.watch(crewProvider);
    final unit = crew.unit;
    if (unit == null) {
      return Scaffold(
        body: crew.loading
            ? const LoadingView(label: 'Загружаем карту…')
            : MessageView.error(crew.error!, onRetry: () => ref.read(crewProvider.notifier).refresh()),
      );
    }
    final incident = crew.assignment;
    final heading = incident != null && (crew.status == UnitStatus.assigned || crew.status == UnitStatus.enRoute);
    final live = heading ? ref.watch(navRouteProvider(incident.id)) : null;
    final fallback = heading ? (incident.my?.route ?? const <LatLng>[]) : const <LatLng>[];
    final routes = <MapRoute>[
      // A dark-blue casing keeps the traffic-coloured line readable on top of
      // the map's own yellow / orange roads.
      if (live != null) ...[
        MapRoute(points: live.geometry, color: JardemColors.primaryDark, width: 12),
        MapRoute.traffic(live),
      ] else if (fallback.length > 1)
        MapRoute(points: fallback, width: 6),
    ];
    final showTraffic = ref.watch(trafficLayerProvider);
    final traffic = showTraffic ? ref.watch(trafficProvider).valueOrNull : null;
    final peers = ref.watch(peersProvider(unit.service));
    final maneuver = crew.status == UnitStatus.enRoute ? nextManeuver(incident?.my?.maneuvers ?? const []) : null;
    final framed = [unit.position, if (incident != null) incident.position, ...?routes.firstOrNull?.points];

    // Keep the vehicle in view while following.
    ref.listen(crewProvider.select((c) => c.unit?.position), (_, next) {
      if (_follow && next != null) _safely(() => _map.move(next, _map.camera.zoom));
    });

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: JardemMap(
              // A new call (or its first route) re-frames the camera.
              key: ValueKey('nav-${incident?.id}-${routes.isNotEmpty}'),
              controller: _map,
              center: unit.position,
              zoom: 14.5,
              fitPoints: incident == null ? null : framed,
              fitPadding: const EdgeInsets.fromLTRB(56, 150, 56, 300),
              units: [
                for (final p in peers)
                  if (p.id != unit.id) MapUnit.of(p, dimBusy: true),
                MapUnit.of(unit, highlighted: true),
              ],
              destination: incident?.position,
              destinationColor: incident == null ? JardemColors.danger : JardemColors.service(incident.service),
              routes: routes,
              traffic: traffic,
              attributionAlignment: Alignment.topLeft,
              attributionPadding: EdgeInsets.fromLTRB(
                8,
                MediaQuery.paddingOf(context).top + (maneuver == null ? 8 : 96),
                8,
                8,
              ),
            ),
          ),
          if (maneuver != null)
            Positioned(left: 12, right: 12, top: 0, child: SafeArea(bottom: false, child: ManeuverBanner(maneuver))),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + (maneuver == null ? 12 : 104),
            child: Column(
              children: [
                SquareIconButton(
                  key: const Key('map-recenter'),
                  icon: _follow ? Icons.navigation_rounded : Icons.near_me_outlined,
                  color: JardemColors.primary,
                  tooltip: 'К моей машине',
                  size: 44,
                  onPressed: () => _recenter(unit.position),
                ),
                const SizedBox(height: 8),
                SquareIconButton(
                  key: const Key('map-layers'),
                  icon: Icons.layers_outlined,
                  color: showTraffic ? JardemColors.primary : JardemColors.muted,
                  tooltip: showTraffic ? 'Скрыть пробки' : 'Показать пробки',
                  size: 44,
                  onPressed: () => ref.read(trafficLayerProvider.notifier).state = !showTraffic,
                ),
                if (incident != null) ...[
                  const SizedBox(height: 8),
                  SquareIconButton(
                    key: const Key('map-overview'),
                    icon: Icons.route_outlined,
                    tooltip: 'Весь маршрут',
                    size: 44,
                    onPressed: () => _overview(framed),
                  ),
                ],
                const SizedBox(height: 16),
                SquareIconButton(
                  key: const Key('map-zoom-in'),
                  icon: Icons.add_rounded,
                  tooltip: 'Приблизить',
                  size: 44,
                  onPressed: () => _zoom(1),
                ),
                const SizedBox(height: 8),
                SquareIconButton(
                  key: const Key('map-zoom-out'),
                  icon: Icons.remove_rounded,
                  tooltip: 'Отдалить',
                  size: 44,
                  onPressed: () => _zoom(-1),
                ),
              ],
            ),
          ),
          // While a call waits for acceptance the incoming-call card takes this place.
          if (crew.incoming == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: incident == null
                  ? _IdleSheet(status: crew.status)
                  : _CallSheet(
                      incident: incident,
                      status: crew.status,
                      onNavigate: () => _openNavigator(incident.position),
                    ),
            ),
        ],
      ),
    );
  }
}

/// «800 м · Поверните направо · ул. Сатпаева».
class ManeuverBanner extends StatelessWidget {
  const ManeuverBanner(this.maneuver, {super.key});

  final Maneuver maneuver;

  static IconData icon(ManeuverArrow arrow) => switch (arrow) {
    ManeuverArrow.left => Icons.turn_left_rounded,
    ManeuverArrow.right => Icons.turn_right_rounded,
    ManeuverArrow.slightLeft => Icons.turn_slight_left_rounded,
    ManeuverArrow.slightRight => Icons.turn_slight_right_rounded,
    ManeuverArrow.uturn => Icons.u_turn_left_rounded,
    ManeuverArrow.arrive => Icons.flag_rounded,
    ManeuverArrow.straight => Icons.straight_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final arrow = arrowFor(maneuver.kind);
    final street = shortStreet(maneuver.street);
    return Container(
      key: const Key('maneuver-banner'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(
        color: JardemColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: JardemColors.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon(arrow), key: Key('arrow-${arrow.name}'), color: Colors.white, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  maneuverDistance(maneuver),
                  style: JardemTheme.text(24, FontWeight.w800, color: Colors.white, height: 1.1),
                ),
                const SizedBox(height: 2),
                Text(
                  street.isEmpty ? maneuverText(maneuver) : '${maneuverText(maneuver)}\n$street',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(14, FontWeight.w600, color: Colors.white, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _sheetDecoration() => const BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  boxShadow: [BoxShadow(color: Color(0x26102A54), blurRadius: 24, offset: Offset(0, -6))],
);

class _IdleSheet extends StatelessWidget {
  const _IdleSheet({required this.status});
  final UnitStatus status;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('nav-idle'),
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: _sheetDecoration(),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: JardemColors.primarySoft, shape: BoxShape.circle),
          child: const Icon(Icons.explore_outlined, color: JardemColors.primaryDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Нет активного вызова', style: JardemTheme.text(16, FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                status == UnitStatus.offDuty
                    ? 'Вы не на смене. Выйдите на смену, чтобы получать вызовы.'
                    : 'Маршрут появится, как только диспетчер назначит вызов.',
                style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CallSheet extends ConsumerWidget {
  const _CallSheet({required this.incident, required this.status, required this.onNavigate});

  final Incident incident;
  final UnitStatus status;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final my = incident.my;
    final moving = status == UnitStatus.enRoute;
    final now = ref.watch(clockProvider)();
    return Container(
      key: const Key('nav-sheet'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: _sheetDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('nav-open-call'),
            onTap: () => context.push('/call'),
            child: Row(
              children: [
                ServiceBadge(incident.service, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        moving ? etaHeadline(my?.etaS) : statusTitle(status),
                        key: const Key('nav-eta'),
                        style: JardemTheme.text(24, FontWeight.w800, height: 1.1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        moving
                            ? arrivalLine(now, etaS: my?.etaS, distanceM: my?.distanceM)
                            : 'Вызов #${incident.number}',
                        style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: JardemColors.faint),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PriorityChip(incident.priority, call: true),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 20, color: JardemColors.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  addressOrPoint(incident),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(14, FontWeight.w700, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            key: const Key('open-navigator'),
            label: 'Открыть в навигаторе',
            icon: Icons.navigation_outlined,
            onPressed: onNavigate,
          ),
          const SizedBox(height: 10),
          const StepButtons(includeShift: false),
        ],
      ),
    );
  }
}
