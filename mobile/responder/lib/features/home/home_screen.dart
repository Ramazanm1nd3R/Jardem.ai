import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/chat.dart';
import '../../logic/details.dart';
import '../../logic/eta.dart';
import '../../logic/steps.dart';
import '../../shared/step_buttons.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';
import '../../state/messages.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

/// «Главная»: who is on shift, counters, crew, vehicle and quick actions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crew = ref.watch(crewProvider);
    final unit = crew.unit;
    if (unit == null) {
      return Scaffold(
        body: crew.loading
            ? const LoadingView(label: 'Загружаем данные экипажа…')
            : MessageView.error(crew.error!, onRetry: () => ref.read(crewProvider.notifier).refresh()),
      );
    }
    final user = ref.watch(sessionProvider)?.user;
    final lead = (user?.name ?? '').isNotEmpty ? user!.name : (unit.lead ?? unit.callsign);
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    final counters = crew.data!.counters;
    final active = crew.incoming == null ? crew.assignment : null;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(crewProvider.notifier).refresh(),
          child: ListView(
            // Leaves room for the incoming-call card.
            padding: EdgeInsets.fromLTRB(16, 12, 16, crew.incoming == null ? 24 : 240),
            children: [
              _Header(lead: lead, unit: unit),
              const SizedBox(height: 12),
              _InfoStrip(city: meta.city),
              if (crew.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Нет связи с сервером — данные могут быть устаревшими.',
                  style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.warning),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Counter(
                      key: const Key('counter-active'),
                      value: counters.active,
                      label: 'Активных\nвызовов',
                      color: JardemColors.danger,
                      icon: Icons.emergency_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Counter(
                      key: const Key('counter-en-route'),
                      value: counters.enRoute,
                      label: 'В пути',
                      color: JardemColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Counter(
                      key: const Key('counter-on-scene'),
                      value: counters.onScene,
                      label: 'На месте',
                      color: JardemColors.success,
                    ),
                  ),
                ],
              ),
              if (unit.status == UnitStatus.offDuty) ...[
                const SizedBox(height: 12),
                JardemCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Вы не на смене', style: JardemTheme.text(15, FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        'Выйдите на смену, чтобы получать вызовы.',
                        style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted),
                      ),
                      const SizedBox(height: 10),
                      StepButton(
                        CrewStep.goOnDuty,
                        service: unit.service,
                        buttonKey: const Key('home-go-on-duty'),
                        height: 48,
                      ),
                    ],
                  ),
                ),
              ],
              if (active != null) ...[const SizedBox(height: 12), _ActiveCall(incident: active, status: crew.status)],
              SectionTitle(myCrewLabel(unit.service)),
              JardemCard(
                key: const Key('home-crew'),
                onTap: () => context.push('/crew'),
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: unit.crew.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'Состав экипажа не указан',
                          style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final m in unit.crew.take(4))
                            Expanded(
                              child: Column(
                                children: [
                                  InitialsAvatar(m.name, radius: 24, online: m.online),
                                  const SizedBox(height: 6),
                                  Text(
                                    m.name.split(' ').first,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: JardemTheme.text(13, FontWeight.w700),
                                  ),
                                  Text(
                                    m.role.split(' · ').first,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: JardemTheme.text(11, FontWeight.w500, color: JardemColors.muted),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              VehicleCard(unit: unit, onTap: () => context.push('/crew?tab=1')),
              const SectionTitle('Быстрые действия'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Action(
                      key: const Key('action-call'),
                      icon: Icons.emergency_share_rounded,
                      color: JardemColors.danger,
                      label: 'Текущий\nвызов',
                      onTap: () => context.push('/call'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      key: const Key('action-map'),
                      icon: Icons.map_rounded,
                      color: JardemColors.primary,
                      label: 'Карта\nвызовов',
                      onTap: () => context.go('/map'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      key: const Key('action-closure'),
                      icon: Icons.block_rounded,
                      color: JardemColors.warning,
                      label: 'Сообщить о\nперекрытии',
                      onTap: () => context.push('/closure'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      key: const Key('action-chat'),
                      icon: Icons.headset_mic_rounded,
                      color: JardemColors.success,
                      label: 'Связь с\nдиспетчером',
                      onTap: () => context.go('/messages'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.lead, required this.unit});

  final String lead;
  final Unit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = badgeText(ref.watch(chatProvider.select((c) => c.unread)));
    return Row(
      children: [
        InitialsAvatar(lead, radius: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lead, maxLines: 1, overflow: TextOverflow.ellipsis, style: JardemTheme.text(17, FontWeight.w800)),
              Text(
                crewTitle(unit.service, unit.callsign),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted),
              ),
              const SizedBox(height: 4),
              InkWell(
                key: const Key('duty-chip'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => context.push('/shift'),
                child: DutyChip(label: dutyLabel(unit.status), onDuty: unit.onDuty),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            SquareIconButton(
              key: const Key('bell'),
              icon: Icons.notifications_none_rounded,
              tooltip: 'Сообщения диспетчера',
              size: 44,
              onPressed: () => context.go('/messages'),
            ),
            if (unread.isNotEmpty)
              Positioned(right: -3, top: -3, child: CountBadge(unread, key: const Key('bell-badge'))),
          ],
        ),
      ],
    );
  }
}

/// «12:24 · Вт, 15 апр. 2025 · Алматы».
class _InfoStrip extends ConsumerStatefulWidget {
  const _InfoStrip({required this.city});
  final String city;

  @override
  ConsumerState<_InfoStrip> createState() => _InfoStripState();
}

class _InfoStripState extends ConsumerState<_InfoStrip> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    return JardemCard(
      shadow: false,
      borderColor: JardemColors.border,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 17, color: JardemColors.navy),
          const SizedBox(width: 6),
          Text(formatClock(now), style: JardemTheme.text(14, FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              formatWeekDate(now),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted),
            ),
          ),
          const Icon(Icons.location_on_outlined, size: 17, color: JardemColors.navy),
          const SizedBox(width: 4),
          Text(widget.city, style: JardemTheme.text(13, FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({super.key, required this.value, required this.label, required this.color, this.icon});

  final int value;
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => JardemCard(
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    child: SizedBox(
      height: 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: JardemTheme.text(20, FontWeight.w800, color: color, height: 1.1)),
                const SizedBox(height: 1),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JardemTheme.text(10.5, FontWeight.w600, color: JardemColors.muted, height: 1.15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The call in progress, one tap from its details.
class _ActiveCall extends StatelessWidget {
  const _ActiveCall({required this.incident, required this.status});

  final Incident incident;
  final UnitStatus status;

  @override
  Widget build(BuildContext context) => JardemCard(
    key: const Key('home-active-call'),
    color: JardemColors.primarySoft,
    borderColor: JardemColors.primary.withValues(alpha: 0.25),
    shadow: false,
    onTap: () => context.push('/call'),
    child: Row(
      children: [
        ServiceBadge(incident.service, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Вызов #${incident.number} · ${statusTitle(status)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(14, FontWeight.w800),
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
        const Icon(Icons.chevron_right_rounded, color: JardemColors.primaryDark),
      ],
    ),
  );
}

/// Photo, callsign, model, plate, fuel and the readiness chip.
class VehicleCard extends StatelessWidget {
  const VehicleCard({super.key, required this.unit, this.onTap});

  final Unit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ready = unit.status == UnitStatus.available || unit.status == UnitStatus.returning;
    return JardemCard(
      key: const Key('vehicle-card'),
      onTap: onTap,
      child: Row(
        children: [
          UnitPhoto(photo: unit.photo, service: unit.service, width: 92, height: 68),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        unit.callsign.isEmpty ? unit.name : unit.callsign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(15, FontWeight.w800),
                      ),
                    ),
                    StatusChip(
                      readinessLabel(unit.status),
                      tone: ready ? ChipTone.success : (unit.onDuty ? ChipTone.warning : ChipTone.neutral),
                    ),
                  ],
                ),
                Text(
                  unit.vehicle.isEmpty ? unit.service.title : unit.vehicle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (unit.plate.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: JardemColors.border, width: 1.5),
                        ),
                        child: Text(unit.plate, style: JardemTheme.text(12, FontWeight.w800)),
                      ),
                    const Spacer(),
                    if (unit.fuelPct != null) ...[
                      const Icon(Icons.local_gas_station_rounded, size: 16, color: JardemColors.muted),
                      const SizedBox(width: 3),
                      Text('${unit.fuelPct}%', style: JardemTheme.text(13, FontWeight.w700)),
                    ],
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

class _Action extends StatelessWidget {
  const _Action({super.key, required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => JardemCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
    child: Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: JardemTheme.text(10.5, FontWeight.w600, height: 1.2),
          ),
        ),
      ],
    ),
  );
}
