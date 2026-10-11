import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/gps.dart';
import '../../logic/steps.dart';
import '../../logic/timeline.dart';
import '../../shared/step_buttons.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';
import '../../state/gps.dart';

/// «Смена и статус»: current status, the timeline and the one button that
/// moves the crew to the next state.
class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crew = ref.watch(crewProvider);
    final unit = crew.unit;
    if (unit == null) {
      return Scaffold(
        appBar: const JardemAppBar(title: 'Смена и статус', fallbackLocation: '/home'),
        body: crew.loading
            ? const LoadingView()
            : MessageView.error(crew.error!, onRetry: () => ref.read(crewProvider.notifier).refresh()),
      );
    }
    final incident = crew.assignment;
    final steps = buildShiftTimeline(
      status: crew.status,
      service: unit.service,
      shiftStartedAt: unit.shiftStartedAt,
      assignment: incident,
      transportAt: incident == null ? null : crew.transportAt[incident.id],
    );
    final my = incident?.my;
    return Scaffold(
      appBar: const JardemAppBar(title: 'Смена и статус', fallbackLocation: '/home'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                JardemCard(
                  key: const Key('status-card'),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: unit.onDuty ? JardemColors.primary : JardemColors.faint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(ServiceIcons.vehicle(unit.service), color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Текущий статус',
                              style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                            ),
                            Text(
                              statusTitle(crew.status),
                              key: const Key('status-title'),
                              style: JardemTheme.text(20, FontWeight.w800),
                            ),
                            if (incident != null)
                              Text(
                                'К вызову #${incident.number}',
                                style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.primaryDark),
                              ),
                            if (crew.status == UnitStatus.enRoute && my?.etaS != null)
                              Text(
                                formatDistanceEta(my?.distanceM, my?.etaS, separator: ' · '),
                                style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < steps.length; i++) _TimelineRow(step: steps[i], last: i == steps.length - 1),
                const SizedBox(height: 8),
                const GpsCard(),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: const StepButtons()),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.last});

  final ShiftStep step;
  final bool last;

  static IconData _icon(String id) => switch (id) {
    'duty' => Icons.check_rounded,
    'accepted' => Icons.call_received_rounded,
    'en_route' => Icons.navigation_rounded,
    'on_scene' => Icons.add_location_alt_rounded,
    'transport' => Icons.airline_seat_flat_rounded,
    _ => Icons.task_alt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final pending = step.phase == StepPhase.pending;
    final active = step.phase == StepPhase.active;
    final color = switch (step.phase) {
      StepPhase.done => JardemColors.success,
      StepPhase.active => JardemColors.primary,
      StepPhase.pending => const Color(0xFFD5DEEC),
    };
    return IntrinsicHeight(
      child: Row(
        key: Key('timeline-${step.id}-${step.phase.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.28), spreadRadius: 4)] : null,
                  ),
                  child: Icon(_icon(step.id), size: 16, color: Colors.white),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: step.phase == StepPhase.done ? color : JardemColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: active ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : const EdgeInsets.only(top: 2),
              decoration: active
                  ? BoxDecoration(color: JardemColors.primarySoft, borderRadius: BorderRadius.circular(12))
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: JardemTheme.text(
                            15,
                            FontWeight.w800,
                            color: pending ? JardemColors.muted : JardemColors.navy,
                          ),
                        ),
                        if (step.subtitle.isNotEmpty)
                          Text(
                            step.subtitle,
                            style: JardemTheme.text(
                              12,
                              FontWeight.w500,
                              color: active ? JardemColors.primaryDark : JardemColors.muted,
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (step.at != null)
                    Text(formatClock(step.at), style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The «Передавать геопозицию» switch with its explanation.
class GpsCard extends ConsumerWidget {
  const GpsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gps = ref.watch(gpsProvider);
    final onDuty = ref.watch(crewProvider.select((c) => c.unit?.onDuty ?? false));
    return JardemCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location_rounded, size: 20, color: JardemColors.navy),
              const SizedBox(width: 10),
              Expanded(child: Text('Передавать геопозицию', style: JardemTheme.text(14.5, FontWeight.w700))),
              Switch(
                key: const Key('gps-switch'),
                value: gps.sharing,
                onChanged: (v) => ref.read(gpsProvider.notifier).setSharing(v),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              gpsHint(sharing: gps.sharing, onDuty: onDuty, lastFixAccepted: gps.lastFixAccepted),
              key: const Key('gps-hint'),
              style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
