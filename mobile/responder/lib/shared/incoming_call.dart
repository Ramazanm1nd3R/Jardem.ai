import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../logic/details.dart';
import '../logic/steps.dart';
import '../state/crew.dart';
import 'step_buttons.dart';
import 'widgets.dart';

/// The prominent «new call» card shown above the bottom navigation on every
/// tab while an assignment waits for «Принять вызов».
class IncomingCallCard extends ConsumerWidget {
  const IncomingCallCard({super.key, required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final my = incident.my;
    final metrics = formatDistanceEta(my?.distanceM, my?.etaS, separator: ' · ');
    return Semantics(
      liveRegion: true,
      label: 'Новый вызов ${incident.number}',
      child: Container(
        key: const Key('incoming-call'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: JardemColors.danger.withValues(alpha: 0.35), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x33102A54), blurRadius: 28, offset: Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: JardemColors.danger, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Новый вызов #${incident.number}',
                    style: JardemTheme.text(13, FontWeight.w800, color: JardemColors.danger),
                  ),
                ),
                PriorityChip(incident.priority),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              key: const Key('incoming-details'),
              onTap: () => context.push('/call'),
              child: Row(
                children: [
                  ServiceBadge(incident.service, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          incident.categoryTitle.isEmpty ? incident.serviceTitle : incident.categoryTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JardemTheme.text(17, FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          addressOrPoint(incident),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  if (metrics != kNoValue) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatDuration(my?.etaS), style: JardemTheme.text(16, FontWeight.w800)),
                        Text(
                          formatDistance(my?.distanceM),
                          style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.muted),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            StepButton(CrewStep.accept, service: incident.service, buttonKey: const Key('incoming-accept'), height: 56),
          ],
        ),
      ),
    );
  }
}

/// Overlay that slides the card in when a call arrives.
class IncomingCallOverlay extends ConsumerWidget {
  const IncomingCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(crewProvider.select((c) => c.incoming));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: incoming == null
          ? const SizedBox.shrink()
          : IncomingCallCard(key: ValueKey(incoming.id), incident: incoming),
    );
  }
}
