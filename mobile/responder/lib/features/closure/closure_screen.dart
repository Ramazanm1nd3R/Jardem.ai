import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../../logic/closures.dart';
import '../../shared/widgets.dart';
import '../../state/closures.dart';
import '../../state/crew.dart';
import '../../state/map.dart';
import '../../state/providers.dart';

/// «Сообщить о перекрытии»: pick a point, pick a reason, send. Reported
/// closures can be lifted from the same screen.
class ClosureScreen extends ConsumerStatefulWidget {
  const ClosureScreen({super.key});

  @override
  ConsumerState<ClosureScreen> createState() => _ClosureScreenState();
}

class _ClosureScreenState extends ConsumerState<ClosureScreen> {
  LatLng? _picked;

  /// Where the vehicle was when the screen opened — the default point. It is
  /// fixed so the pin does not drift while the vehicle keeps moving.
  LatLng? _start;
  String _reason = kClosureReasons.first;
  bool _busy = false;
  String? _lifting;

  Future<void> _report(LatLng at) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(myClosuresProvider.notifier).report(at, _reason);
      toast(messenger, 'Перекрытие отмечено. Маршруты экипажей пересчитаны.');
    } catch (e) {
      final outside = e is ApiException && (e.isUnprocessable || e.isNotFound);
      toast(messenger, outside ? 'В этой точке нет дороги в пределах Алматы. Выберите другую.' : errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lift(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _lifting = id);
    try {
      await ref.read(myClosuresProvider.notifier).lift(id);
      toast(messenger, 'Перекрытие снято.');
    } catch (e) {
      toast(messenger, errorMessage(e));
    } finally {
      if (mounted) setState(() => _lifting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(crewProvider.select((c) => c.unit));
    final area = ref.watch(metaProvider).valueOrNull?.bbox ?? kAlmatyBounds;
    final traffic = ref.watch(trafficProvider);
    final mine = ref.watch(myClosuresProvider);
    _start ??= unit?.position;
    final point = _picked ?? _start ?? kDemoPoint;
    final closures = traffic.valueOrNull?.closures ?? const <RoadClosure>[];
    ref.listen(trafficProvider, (_, next) {
      final data = next.valueOrNull;
      if (data != null && !next.isLoading) ref.read(myClosuresProvider.notifier).sync(data.closures);
    });
    return Scaffold(
      appBar: const JardemAppBar(title: 'Сообщить о перекрытии', fallbackLocation: '/home'),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.3,
            child: Stack(
              children: [
                Positioned.fill(
                  child: JardemMap(
                    key: const Key('closure-map'),
                    center: point,
                    zoom: 15,
                    // The vehicle is the blue dot; the pin marks the closure point.
                    myLocation: unit?.position,
                    destination: point,
                    destinationColor: TrafficLevel.closed.color,
                    traffic: traffic.valueOrNull,
                    onTap: (p) {
                      if (inServiceArea(p, area)) {
                        setState(() => _picked = p);
                      } else {
                        toast(ScaffoldMessenger.of(context), 'Точка вне Алматы.');
                      }
                    },
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _picked == null
                          ? 'Точка: текущее положение машины. Нажмите на карту, чтобы выбрать другую.'
                          : 'Точка выбрана на карте.',
                      key: const Key('closure-point'),
                      style: JardemTheme.text(12, FontWeight.w600, height: 1.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Text('Причина', style: JardemTheme.text(13, FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in kClosureReasons)
                      ChoiceChip(
                        key: Key('reason-$r'),
                        label: Text(r),
                        selected: r == _reason,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _reason = r),
                        selectedColor: JardemColors.primary,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: r == _reason ? JardemColors.primary : JardemColors.border),
                        labelStyle: JardemTheme.text(
                          13,
                          FontWeight.w700,
                          color: r == _reason ? Colors.white : JardemColors.navy,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Перекрытие сразу учитывается в маршрутах всех экипажей и действует $kClosureMinutes минут, пока его не снимут.',
                  style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  key: const Key('closure-submit'),
                  label: 'Сообщить о перекрытии',
                  icon: Icons.block_rounded,
                  color: JardemColors.warning,
                  radius: 16,
                  loading: _busy,
                  onPressed: () => _report(point),
                ),
                const SectionTitle('Активные перекрытия'),
                if (traffic.isLoading && !traffic.hasValue)
                  const Padding(padding: EdgeInsets.all(16), child: LoadingView())
                else if (traffic.hasError && !traffic.hasValue)
                  MessageView.error(traffic.error!, compact: true, onRetry: () => ref.invalidate(trafficProvider))
                else if (closures.isEmpty)
                  Text(
                    'Перекрытий нет.',
                    key: const Key('closures-empty'),
                    style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted),
                  )
                else
                  for (final c in closures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: JardemCard(
                        key: Key('closure-${c.id}'),
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Row(
                          children: [
                            Icon(Icons.block_rounded, color: TrafficLevel.closed.color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(closureTitle(c), style: JardemTheme.text(14, FontWeight.w700)),
                                  Text(
                                    '${c.lat.toStringAsFixed(4)}, ${c.lon.toStringAsFixed(4)}'
                                    '${canLift(c, mine) ? ' · отмечено вами' : ''}',
                                    style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                                  ),
                                ],
                              ),
                            ),
                            if (canLift(c, mine))
                              TextButton(
                                key: Key('lift-${c.id}'),
                                onPressed: _lifting == c.id ? null : () => _lift(c.id),
                                child: const Text('Снять'),
                              ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
