import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/details.dart';
import '../../logic/steps.dart';
import '../../shared/step_buttons.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';

/// «Вызов #45821»: everything known about the current assignment.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final crew = ref.watch(crewProvider);
    final incident = crew.assignment;
    final unit = crew.unit;
    if (incident == null || unit == null) {
      return Scaffold(
        appBar: const JardemAppBar(title: 'Текущий вызов', fallbackLocation: '/home'),
        body: crew.loading
            ? const LoadingView()
            : const MessageView(
                icon: Icons.inbox_outlined,
                title: 'Нет активного вызова',
                text: 'Когда диспетчер назначит вызов, он появится здесь и на всех экранах приложения.',
              ),
      );
    }
    final steps = nextSteps(crew.status, unit.service).where((s) => s.action != null).toList();
    final ambulance = incident.service == ServiceType.ambulance;
    return Scaffold(
      appBar: JardemAppBar(title: 'Вызов #${incident.number}', fallbackLocation: '/home'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                ServiceBadge(incident.service, size: 52, circle: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PriorityChip(incident.priority),
                          const Spacer(),
                          Text(
                            formatClock(incident.createdAt),
                            style: JardemTheme.text(13, FontWeight.w700, color: JardemColors.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        incident.categoryTitle.isEmpty ? incident.serviceTitle : incident.categoryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(18, FontWeight.w800),
                      ),
                      Text(
                        '${incident.serviceTitle} · ${statusTitle(crew.status)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentTabs(
              labels: ['Детали', 'Карта', ambulance ? 'Пострадавший' : 'Сведения'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_tab) {
              0 => _Details(incident: incident),
              1 => _MapTab(incident: incident, unit: unit),
              _ => _Facts(incident: incident, ambulance: ambulance),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in steps) ...[
                    StepButton(s, key: ValueKey(s), service: unit.service),
                    const SizedBox(height: 10),
                  ],
                  SecondaryButton(
                    key: const Key('call-caller'),
                    label: incident.callerPhone.isEmpty ? 'Телефон заявителя не указан' : 'Позвонить заявителю',
                    icon: Icons.phone_rounded,
                    height: 50,
                    onPressed: incident.callerPhone.isEmpty ? null : () => dial(context, ref, incident.callerPhone),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.incident});
  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    children: [
      JardemCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            InfoRow(icon: Icons.location_on_outlined, label: 'Адрес', value: addressOrPoint(incident)),
            const Divider(),
            InfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Заявитель',
              value: [
                if (incident.callerName.isNotEmpty) incident.callerName,
                if (incident.callerPhone.isNotEmpty) incident.callerPhone,
              ].join('\n').ifEmpty('Не указан'),
              trailing: incident.callerPhone.isEmpty
                  ? null
                  : SquareIconButton(
                      key: const Key('call-caller-icon'),
                      icon: Icons.phone_rounded,
                      color: JardemColors.primary,
                      tooltip: 'Позвонить заявителю',
                      size: 42,
                      bordered: true,
                      onPressed: () => dial(context, ref, incident.callerPhone),
                    ),
            ),
          ],
        ),
      ),
      const SectionTitle('Описание'),
      Text(
        incident.description.trim().isEmpty ? 'Заявитель не оставил описания.' : incident.description.trim(),
        style: JardemTheme.text(14, FontWeight.w500, height: 1.45),
      ),
      if (incident.extraInfo.trim().isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          key: const Key('extra-info'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: JardemColors.dangerSoft, borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 20, color: JardemColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Дополнительная информация',
                      style: JardemTheme.text(13, FontWeight.w800, color: JardemColors.danger),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      incident.extraInfo.trim(),
                      style: JardemTheme.text(13, FontWeight.w500, color: const Color(0xFFB02A2A), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _MapTab extends StatelessWidget {
  const _MapTab({required this.incident, required this.unit});
  final Incident incident;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final route = incident.my?.route ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: JardemMap(
          key: const Key('call-map'),
          center: incident.position,
          zoom: 15,
          fitPoints: [unit.position, incident.position, ...route],
          units: [MapUnit.of(unit, highlighted: true)],
          destination: incident.position,
          destinationColor: JardemColors.service(incident.service),
          routes: [if (route.length > 1) MapRoute(points: route, width: 5)],
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.incident, required this.ambulance});
  final Incident incident;
  final bool ambulance;

  static IconData _icon(String label) => switch (label) {
    'Угроза жизни' => Icons.monitor_heart_outlined,
    'Возраст' => Icons.cake_outlined,
    'Пострадавших' => Icons.groups_2_outlined,
    'Люди внутри' => Icons.meeting_room_outlined,
    _ => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final facts = triageFacts(incident.triage);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        JardemCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              InfoRow(
                icon: Icons.category_outlined,
                label: 'Тип вызова',
                value: incident.categoryTitle.isEmpty ? incident.serviceTitle : incident.categoryTitle,
              ),
              for (final f in facts) ...[
                const Divider(),
                InfoRow(icon: _icon(f.label), label: f.label, value: f.value, alert: f.alert),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          facts.isEmpty
              ? 'Автоматическая оценка обращения недоступна — уточните обстановку у заявителя.'
              : 'Сведения получены автоматическим разбором слов заявителя и могут быть неточными'
                    '${ambulance ? ' — оцените состояние пострадавшего на месте.' : '.'}',
          style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.4),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
