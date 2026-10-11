import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/dial.dart';
import '../../state/location.dart';
import '../../state/providers.dart';
import '../../state/traffic.dart';
import '../../state/units.dart';
import 'home_widgets.dart';

/// Whether the demo disclaimer banner was closed in this session.
final disclaimerDismissedProvider = StateProvider<bool>((ref) => false);

/// Home tab: live map of all on-duty units and the service picker.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _map = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(announce: false));
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _moveTo(LatLng point) {
    if (!_mapReady) return;
    _map.move(point, _map.camera.zoom < 13 ? 14 : _map.camera.zoom);
  }

  Future<void> _locate({bool announce = true}) async {
    final loc = await ref.read(locationProvider.notifier).locate();
    if (!mounted) return;
    _moveTo(loc.point);
    if (announce && loc.reason != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(loc.reason!)));
    }
  }

  void _onLongPress(LatLng point) {
    final ok = ref.read(locationProvider.notifier).setManual(point);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? 'Местоположение изменено' : 'Эта точка вне зоны обслуживания Алматы'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationProvider);
    final units = ref.watch(unitsProvider(const UnitsQuery()));
    final trafficOn = ref.watch(trafficLayerProvider);
    final traffic = trafficOn ? ref.watch(trafficProvider) : null;
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    final dismissed = ref.watch(disclaimerDismissedProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: JardemMap(
            controller: _map,
            center: location.point,
            zoom: 13.6,
            units: [for (final u in units.valueOrNull ?? const <Unit>[]) MapUnit.of(u, dimBusy: true)],
            myLocation: location.point,
            traffic: traffic?.valueOrNull,
            onLongPress: _onLongPress,
            onMapReady: () => _mapReady = true,
            attributionAlignment: Alignment.bottomLeft,
            attributionPadding: const EdgeInsets.only(left: 8, bottom: 158),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: LocationHeader(location: location)),
                    const SizedBox(width: 8),
                    SquareIconButton(
                      icon: Icons.person_outline_rounded,
                      tooltip: 'Профиль',
                      onPressed: () => context.go('/profile'),
                    ),
                  ],
                ),
                if (!dismissed) ...[
                  const SizedBox(height: 8),
                  DisclaimerBanner(
                    text: meta.disclaimer,
                    onClose: () => ref.read(disclaimerDismissedProvider.notifier).state = true,
                  ),
                ],
                if (units.hasError && !units.hasValue) ...[
                  const SizedBox(height: 8),
                  InlineNotice(
                    text: 'Не удалось загрузить экипажи. ${errorMessage(units.error!)}',
                    actionLabel: 'Повторить',
                    onAction: () => ref.read(unitsProvider(const UnitsQuery()).notifier).refresh(),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (trafficOn)
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: TrafficLegend(traffic: traffic, onRetry: () => ref.invalidate(trafficProvider)),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SquareIconButton(
                          icon: Icons.near_me_outlined,
                          tooltip: 'Моё местоположение',
                          onPressed: _locate,
                        ),
                        const SizedBox(height: 8),
                        SquareIconButton(
                          icon: Icons.layers_outlined,
                          tooltip: 'Слой пробок',
                          color: trafficOn ? JardemColors.primary : JardemColors.navy,
                          onPressed: () => ref.read(trafficLayerProvider.notifier).state = !trafficOn,
                        ),
                        const SizedBox(height: 8),
                        EmergencyCallButton(
                          number: meta.emergencyPhone,
                          onPressed: () => dial(context, ref, meta.emergencyPhone),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ServiceSheet(
            loading: units.isLoading && !units.hasValue,
            onService: (s) => context.go('/map/service/${s.id}'),
            onOther: () => context.push('/other'),
          ),
        ),
      ],
    );
  }
}
