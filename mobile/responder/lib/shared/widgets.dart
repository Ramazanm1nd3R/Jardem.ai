import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../logic/details.dart';
import '../state/providers.dart';

/// Back chevron + centred title, as on the inner screens of the mock-up.
///
/// When the screen was opened directly (deep link, or after `go`), the chevron
/// leads to [fallbackLocation] instead of popping.
class JardemAppBar extends StatelessWidget implements PreferredSizeWidget {
  const JardemAppBar({super.key, required this.title, this.actions, this.fallbackLocation});

  final String title;
  final List<Widget>? actions;
  final String? fallbackLocation;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final fallback = fallbackLocation;
    return AppBar(
      toolbarHeight: 52,
      automaticallyImplyLeading: false,
      leading: canPop || fallback != null
          ? IconButton(
              tooltip: 'Назад',
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
              onPressed: () => canPop ? Navigator.of(context).maybePop() : GoRouter.of(context).go(fallback!),
            )
          : null,
      title: Text(title),
      actions: actions,
    );
  }
}

/// «Моя бригада» for an ambulance, «Мой экипаж» for the other services.
String myCrewLabel(ServiceType? service) =>
    service == null || service == ServiceType.ambulance ? 'Моя бригада' : 'Мой экипаж';

/// Shows [text] right away, replacing a snackbar that is still on screen.
void toast(ScaffoldMessengerState? messenger, String text) => messenger
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// Opens the dialler for [number]; tells the user the number if that fails.
Future<void> dial(BuildContext context, WidgetRef ref, String number) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await ref.read(dialerProvider)(number);
  if (!ok) {
    toast(messenger, 'Не удалось открыть звонок. Наберите $number вручную.');
  }
}

/// Round avatar with initials (the demo has no crew photos).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.radius = 22, this.online});

  final String? name;
  final double radius;

  /// Draws a presence dot when non-null.
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: JardemColors.primarySoft,
      child: Text(
        initials(name),
        style: JardemTheme.text(radius * 0.68, FontWeight.w800, color: JardemColors.primaryDark),
      ),
    );
    if (online == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: radius * 0.5,
            height: radius * 0.5,
            decoration: BoxDecoration(
              color: online! ? JardemColors.success : JardemColors.faint,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Segmented pill tabs: «Состав · Транспорт · Оборудование».
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.badges = const {},
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Small red counters by tab index.
  final Map<int, String> badges;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: JardemColors.border),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Material(
              color: i == index ? JardemColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('tab-$i'),
                onTap: () => onChanged(i),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(
                          13,
                          i == index ? FontWeight.w700 : FontWeight.w600,
                          color: i == index ? Colors.white : JardemColors.muted,
                        ),
                      ),
                    ),
                    if ((badges[i] ?? '').isNotEmpty) ...[const SizedBox(width: 4), CountBadge(badges[i]!)],
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Red counter dot.
class CountBadge extends StatelessWidget {
  const CountBadge(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 17),
    height: 17,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: JardemColors.danger, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: JardemTheme.text(10, FontWeight.w800, color: Colors.white, height: 1)),
  );
}

/// «Экстренный» (red) / «Срочный» (orange) / calm chip for lower priorities.
class PriorityChip extends StatelessWidget {
  const PriorityChip(this.priority, {super.key, this.call = false});

  final int priority;

  /// «Экстренный вызов» instead of «Экстренный».
  final bool call;

  @override
  Widget build(BuildContext context) => StatusChip(
    call ? priorityCallLabel(priority) : priorityLabel(priority),
    tone: isCritical(priority) ? ChipTone.danger : (isUrgent(priority) ? ChipTone.warning : ChipTone.info),
    icon: isCritical(priority) ? Icons.notifications_active_rounded : null,
  );
}

/// «На смене» (green) / «Не на смене» (outlined grey).
class DutyChip extends StatelessWidget {
  const DutyChip({super.key, required this.label, required this.onDuty});

  final String label;
  final bool onDuty;

  @override
  Widget build(BuildContext context) {
    final fg = onDuty ? JardemColors.success : JardemColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onDuty ? JardemColors.successSoft : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onDuty ? JardemColors.successSoft : JardemColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(onDuty ? Icons.verified_user_outlined : Icons.pause_circle_outline_rounded, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label, style: JardemTheme.text(12, FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// Section heading such as «Моя бригада».
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: JardemTheme.text(16, FontWeight.w800))),
        ?trailing,
      ],
    ),
  );
}

/// Amber note: «Демо-режим: вызовы и экипажи смоделированы».
class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key, this.text = kDemoNotice});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFE2A8)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF7A5210)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: JardemTheme.text(12, FontWeight.w600, color: const Color(0xFF7A5210), height: 1.3)),
        ),
      ],
    ),
  );
}

/// Icon in a soft circle followed by label / value lines.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.alert = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool alert;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: alert ? JardemColors.danger : JardemColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted)),
              const SizedBox(height: 2),
              Text(
                value,
                style: JardemTheme.text(
                  14,
                  FontWeight.w700,
                  color: alert ? JardemColors.danger : JardemColors.navy,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}
