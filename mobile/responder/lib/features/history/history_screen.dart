import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/details.dart';
import '../../logic/history.dart';
import '../../shared/widgets.dart';
import '../../state/map.dart';
import '../../state/providers.dart';

/// «История вызовов»: finished calls grouped by day.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryFilter _filter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: const JardemAppBar(title: 'История вызовов'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentTabs(
              labels: [for (final f in HistoryFilter.values) f.label],
              index: _filter.index,
              onChanged: (i) => setState(() => _filter = HistoryFilter.values[i]),
            ),
          ),
          Expanded(
            child: history.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => MessageView.error(e, onRetry: () => ref.invalidate(historyProvider)),
              data: (incidents) {
                final days = groupByDay(incidents, now, filter: _filter);
                if (days.isEmpty) {
                  return MessageView(
                    icon: Icons.history_rounded,
                    title: _filter == HistoryFilter.today ? 'Сегодня вызовов не было' : 'История пуста',
                    text: 'Отработанные вызовы экипажа появятся здесь.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(historyProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final day in days) ...[
                        Padding(
                          key: Key('day-${day.label}'),
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Text(day.label, style: JardemTheme.text(13, FontWeight.w800)),
                        ),
                        JardemCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: [
                              for (var i = 0; i < day.incidents.length; i++) ...[
                                if (i > 0) const Divider(indent: 46),
                                _HistoryRow(day.incidents[i]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.incident);
  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final cancelled = incident.status == IncidentStatus.cancelled;
    final resolved = incident.status == IncidentStatus.resolved;
    final color = cancelled
        ? JardemColors.faint
        : (resolved ? JardemColors.success : JardemColors.service(incident.service));
    final arrival = historyArrival(incident);
    return Padding(
      key: Key('history-${incident.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: cancelled
                ? const Icon(Icons.close_rounded, size: 18, color: Colors.white)
                : (resolved
                      ? const Icon(Icons.check_rounded, size: 19, color: Colors.white)
                      : ServiceIcon(incident.service, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${incident.number}', style: JardemTheme.text(12, FontWeight.w800, color: JardemColors.muted)),
                Text(
                  historyTitle(incident),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(14, FontWeight.w700),
                ),
                Text(
                  addressOrPoint(incident),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatClock(incident.createdAt),
                style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.muted),
              ),
              const SizedBox(height: 14),
              Text(cancelled ? 'Отменён' : arrival, style: JardemTheme.text(13, FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}
