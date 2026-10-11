import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/details.dart';
import '../../logic/steps.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';
import '../home/home_screen.dart';

/// «Моя бригада»: Состав · Транспорт · Оборудование.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  late int _tab = widget.initialTab.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final crew = ref.watch(crewProvider);
    final unit = crew.unit;
    if (unit == null) {
      return Scaffold(
        appBar: const JardemAppBar(title: 'Моя бригада', fallbackLocation: '/home'),
        body: crew.loading
            ? const LoadingView()
            : MessageView.error(crew.error!, onRetry: () => ref.read(crewProvider.notifier).refresh()),
      );
    }
    final equipment = equipmentSummary(unit.equipment);
    final ambulance = unit.service == ServiceType.ambulance;
    return Scaffold(
      appBar: JardemAppBar(title: myCrewLabel(unit.service), fallbackLocation: '/home'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              ServiceBadge(unit.service, size: 44, circle: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.callsign.isEmpty ? unit.name : unit.callsign,
                      style: JardemTheme.text(18, FontWeight.w800),
                    ),
                    if (unit.departmentName.isNotEmpty)
                      Text(
                        unit.departmentName,
                        style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                      ),
                  ],
                ),
              ),
              DutyChip(label: dutyLabel(unit.status), onDuty: unit.onDuty),
            ],
          ),
          const SizedBox(height: 14),
          SegmentTabs(
            labels: const ['Состав', 'Транспорт', 'Оборудование'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_tab == 0) ...[
            SectionTitle(ambulance ? 'Члены бригады' : 'Состав экипажа'),
            if (unit.crew.isEmpty)
              const MessageView(icon: Icons.groups_outlined, title: 'Состав не указан', compact: true)
            else
              JardemCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < unit.crew.length; i++) ...[
                      if (i > 0) const Divider(indent: 56),
                      _Member(unit.crew[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Состав ${ambulance ? 'бригады' : 'экипажа'} формирует диспетчерская; изменить его из приложения нельзя.',
              style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.4),
            ),
          ],
          if (_tab == 1) ...[
            const SectionTitle('Транспорт'),
            VehicleCard(unit: unit),
            const SizedBox(height: 12),
            JardemCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  InfoRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Автомобиль',
                    value: unit.vehicle.isEmpty ? kNoValue : unit.vehicle,
                  ),
                  const Divider(),
                  InfoRow(
                    icon: Icons.pin_outlined,
                    label: 'Гос. номер',
                    value: unit.plate.isEmpty ? kNoValue : unit.plate,
                  ),
                  const Divider(),
                  InfoRow(
                    icon: Icons.local_gas_station_outlined,
                    label: 'Топливо',
                    value: unit.fuelPct == null ? kNoValue : '${unit.fuelPct}%',
                  ),
                  const Divider(),
                  InfoRow(
                    icon: Icons.home_work_outlined,
                    label: 'Подразделение',
                    value: unit.departmentName.isEmpty ? kNoValue : unit.departmentName,
                  ),
                ],
              ),
            ),
          ],
          if (_tab == 2) ...[
            SectionTitle(
              equipment.title,
              trailing: StatusChip(
                equipment.status,
                tone: equipment.ok ? ChipTone.success : ChipTone.warning,
                icon: equipment.ok ? Icons.check_rounded : Icons.warning_amber_rounded,
              ),
            ),
            if (unit.equipment.isEmpty)
              const MessageView(icon: Icons.medical_services_outlined, title: 'Список оборудования пуст', compact: true)
            else
              JardemCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < unit.equipment.length; i++) ...[
                      if (i > 0) const Divider(indent: 44),
                      _Equipment(unit.equipment[i]),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Member extends StatelessWidget {
  const _Member(this.member);
  final CrewMember member;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        InitialsAvatar(member.name, radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(14.5, FontWeight.w700),
              ),
              Text(
                member.role.isEmpty ? 'Член экипажа' : member.role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusChip(member.online ? 'Онлайн' : 'Не в сети', tone: member.online ? ChipTone.success : ChipTone.neutral),
      ],
    ),
  );
}

class _Equipment extends StatelessWidget {
  const _Equipment(this.item);
  final EquipmentItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: item.ok ? JardemColors.success : JardemColors.warning,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(item.ok ? Icons.check_rounded : Icons.priority_high_rounded, size: 17, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: JardemTheme.text(14, FontWeight.w700)),
              if (item.detail.isNotEmpty)
                Text(item.detail, style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}
