import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/widgets.dart';
import '../../state/incidents.dart';
import 'incident_card.dart';

/// «Вызовы» tab: active calls, tap → tracking.
class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _IncidentListView(
    title: 'Вызовы',
    select: (l) => l.active,
    empty: MessageView(
      icon: Icons.phone_in_talk_outlined,
      title: 'Нет активных вызовов',
      text: 'Когда вы вызовете службу, здесь появится её статус.',
      actionLabel: 'Открыть карту',
      onAction: () => context.go('/map'),
    ),
    onTap: (i) => context.push('/tracking/${i.id}'),
  );
}

/// «История» tab (also opened from the profile): closed calls.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, this.title = 'История', this.fallbackLocation});

  final String title;
  final String? fallbackLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _IncidentListView(
    title: title,
    fallbackLocation: fallbackLocation,
    select: (l) => l.history,
    empty: const MessageView(
      icon: Icons.history_rounded,
      title: 'История пуста',
      text: 'Здесь будут завершённые и отменённые вызовы.',
    ),
    onTap: (i) => context.push('/tracking/${i.id}'),
  );
}

class _IncidentListView extends ConsumerWidget {
  const _IncidentListView({
    required this.title,
    required this.select,
    required this.empty,
    required this.onTap,
    this.fallbackLocation,
  });

  final String? fallbackLocation;

  final String title;
  final List<Incident> Function(IncidentList) select;
  final Widget empty;
  final ValueChanged<Incident> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidents = ref.watch(incidentsProvider);
    Future<void> reload() => ref.refresh(incidentsProvider.future).then((_) {}, onError: (_) {});
    return Scaffold(
      appBar: JardemAppBar(title: title, fallbackLocation: fallbackLocation),
      body: incidents.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const LoadingView(),
        error: (e, _) => MessageView.error(e, onRetry: () => ref.invalidate(incidentsProvider)),
        data: (all) {
          final list = select(all);
          return RefreshIndicator(
            onRefresh: reload,
            child: list.isEmpty
                ? LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(height: box.maxHeight, child: empty),
                    ),
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => IncidentCard(incident: list[i], onTap: () => onTap(list[i])),
                  ),
          );
        },
      ),
    );
  }
}
