import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/dial.dart';
import '../../shared/widgets.dart';
import '../../state/incidents.dart';
import '../../state/providers.dart';
import 'call_stepper.dart';

/// Live tracking of one call: stepper, map, ETA, crew card and actions.
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, required this.incidentId});

  final String incidentId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final _map = MapController();
  bool _mapReady = false;
  bool _framed = false;
  bool _cancelling = false;
  IncidentStatus? _lastStatus;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _frame(Incident incident, Unit? unit, {bool force = false}) {
    if (!_mapReady || (_framed && !force)) return;
    final fit = JardemMap.fitFor([
      incident.position,
      if (unit != null) unit.position,
      ...?unit?.route,
    ], const EdgeInsets.fromLTRB(48, 120, 48, 56));
    if (fit != null) {
      _map.fitCamera(fit);
      _framed = unit != null;
    } else {
      _map.move(incident.position, 15);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить вызов?'),
        content: const Text(
          'Экипаж получит уведомление об отмене. Отменяйте вызов, только если помощь больше не нужна.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Не отменять')),
          TextButton(
            key: const Key('cancel-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: JardemColors.danger),
            child: const Text('Отменить вызов'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(trackingProvider(widget.incidentId).notifier).cancel();
      ref.invalidate(incidentsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Вызов отменён')));
    } catch (e) {
      final text = e is ApiException && e.isConflict ? 'Экипаж уже на месте — отменить вызов нельзя.' : errorMessage(e);
      messenger.showSnackBar(SnackBar(content: Text(text)));
      ref.read(trackingProvider(widget.incidentId).notifier).refresh();
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _showChatInfo() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Чат с экипажем', style: JardemTheme.text(18, FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'В демо-версии переписка с экипажем недоступна: экипажи смоделированы и не могут ответить. '
            'Если нужно срочно сообщить что-то важное — позвоните по номеру службы.',
            style: JardemTheme.text(14, FontWeight.w500, color: JardemColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Понятно', height: 48, onPressed: () => Navigator.pop(context)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingProvider(widget.incidentId));
    final incident = state.incident;
    final title = incident == null ? 'Вызов' : citizenStatusTitle(incident.status);

    return Scaffold(
      appBar: JardemAppBar(
        title: title,
        fallbackLocation: '/calls',
        actions: [
          if (incident != null && incident.status.canCancel)
            TextButton(
              key: const Key('tracking-cancel'),
              onPressed: _cancelling ? null : _cancel,
              style: TextButton.styleFrom(foregroundColor: JardemColors.danger),
              child: const Text('Отменить'),
            ),
        ],
      ),
      body: incident == null
          ? (state.error != null
                ? MessageView.error(
                    state.error!,
                    onRetry: () => ref.read(trackingProvider(widget.incidentId).notifier).refresh(),
                  )
                : const LoadingView(label: 'Загружаем вызов…'))
          : _body(context, incident, state),
    );
  }

  Widget _body(BuildContext context, Incident incident, TrackingState state) {
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    final color = JardemColors.service(incident.service);
    final live = incident.primaryUnit;
    final unit = live ?? state.unit;
    final moving = incident.status == IncidentStatus.assigned || incident.status == IncidentStatus.enRoute;
    final closed = incident.status.isClosed;

    final arrived = !moving && _lastStatus != incident.status;
    _lastStatus = incident.status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (arrived && _mapReady && incident.status != IncidentStatus.created) {
        // The crew is here (or the call is closed): centre on the address.
        _map.move(incident.position, 16);
      } else {
        _frame(incident, live);
      }
    });

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: CallStepper(status: incident.status),
          ),
          if (state.error != null)
            Container(
              width: double.infinity,
              color: JardemColors.warningSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Нет связи с сервером — данные могут быть неактуальны. Повторяем…',
                style: JardemTheme.text(11.5, FontWeight.w600, color: const Color(0xFF9A5B0B)),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: JardemMap(
                    controller: _map,
                    center: incident.position,
                    zoom: 14.5,
                    myLocation: incident.position,
                    units: [if (live != null && !closed) MapUnit.of(live, highlighted: true)],
                    routes: [
                      if (live != null && moving && live.route.length > 1)
                        MapRoute(points: live.route, color: color, dashed: true, width: 3),
                    ],
                    onMapReady: () {
                      _mapReady = true;
                      _frame(incident, live);
                    },
                    moveDuration: const Duration(milliseconds: 1500),
                    attributionPadding: const EdgeInsets.only(left: 8, bottom: 8),
                  ),
                ),
                if (moving && live != null && live.etaS != null)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: JardemCard(
                      key: const Key('eta-chip'),
                      radius: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatDuration(live.etaS), style: JardemTheme.text(16, FontWeight.w800)),
                          if (live.distanceM != null)
                            Text(
                              formatDistance(live.distanceM),
                              style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (live != null && !closed)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: SquareIconButton(
                      icon: Icons.center_focus_strong_rounded,
                      color: JardemColors.primary,
                      size: 42,
                      tooltip: 'Показать экипаж и меня',
                      onPressed: () => _frame(incident, live, force: true),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [BoxShadow(color: Color(0x1F1A4B8C), blurRadius: 24, offset: Offset(0, -6))],
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Summary(incident: incident),
                if (unit != null)
                  UnitCard(
                    unit: unit,
                    flat: true,
                    subtitle: [
                      incident.serviceTitle,
                      if (incident.categoryTitle.isNotEmpty) incident.categoryTitle,
                    ].join(' • '),
                    extraLine: unit.plate.isEmpty ? unit.vehicle : 'Гос. номер: ${unit.plate}',
                  )
                else if (!closed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Подбираем ближайший свободный экипаж…',
                            style: JardemTheme.text(14, FontWeight.w600, color: JardemColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                if (closed)
                  PrimaryButton(label: 'На главную', height: 48, radius: 14, onPressed: () => context.go('/map'))
                else
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          key: const Key('tracking-dial'),
                          label: 'Позвонить',
                          icon: Icons.phone_rounded,
                          onPressed: () => dial(context, ref, meta.phoneOf(incident.service)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SecondaryButton(
                          key: const Key('tracking-chat'),
                          label: 'Написать',
                          icon: Icons.chat_bubble_outline_rounded,
                          onPressed: _showChatInfo,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Short result block once the crew has arrived or the call is closed.
class _Summary extends StatelessWidget {
  const _Summary({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final arrival = timeToArrivalS(
      firstArrivalS: incident.firstArrivalS,
      createdAt: incident.createdAt,
      arrivedAt: incident.reachedAt(IncidentStatus.onScene),
    );
    final (IconData icon, Color color, String title, String? text) = switch (incident.status) {
      IncidentStatus.onScene => (
        Icons.check_circle_rounded,
        JardemColors.success,
        'Экипаж на месте',
        arrival == null ? null : 'Время прибытия: ${formatDuration(arrival)}',
      ),
      IncidentStatus.resolved => (
        Icons.check_circle_rounded,
        JardemColors.success,
        'Вызов завершён',
        arrival == null ? 'Спасибо, что воспользовались Jardem.ai' : 'Экипаж прибыл за ${formatDuration(arrival)}',
      ),
      IncidentStatus.cancelled => (Icons.cancel_rounded, JardemColors.muted, 'Вызов отменён', null),
      _ => (Icons.info, JardemColors.muted, '', null),
    };
    if (title.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('tracking-summary'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Color.lerp(color, Colors.white, 0.9), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: JardemTheme.text(15, FontWeight.w800)),
                if (text != null) Text(text, style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted)),
              ],
            ),
          ),
          Text('№ ${incident.number}', style: JardemTheme.text(12, FontWeight.w700, color: JardemColors.muted)),
        ],
      ),
    );
  }
}
