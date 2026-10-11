import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/jardem_colors.dart';
import '../theme/jardem_theme.dart';

enum ChipTone { success, warning, danger, info, neutral }

/// Small pill such as «Свободен» (green) or «Занят» (orange).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral, this.icon});

  /// Citizen-facing unit availability chip.
  factory StatusChip.unit(UnitStatus status, {Key? key}) => StatusChip(
    status.chipLabel,
    key: key,
    tone: switch (status) {
      UnitStatus.available => ChipTone.success,
      UnitStatus.offDuty || UnitStatus.unknown => ChipTone.neutral,
      _ => ChipTone.warning,
    },
  );

  factory StatusChip.incident(IncidentStatus status, {Key? key}) => StatusChip(
    status.label,
    key: key,
    tone: switch (status) {
      IncidentStatus.resolved || IncidentStatus.onScene => ChipTone.success,
      IncidentStatus.cancelled => ChipTone.neutral,
      IncidentStatus.enRoute => ChipTone.info,
      _ => ChipTone.warning,
    },
  );

  final String label;
  final ChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (tone) {
      ChipTone.success => (JardemColors.success, JardemColors.successSoft),
      ChipTone.warning => (JardemColors.warning, JardemColors.warningSoft),
      ChipTone.danger => (JardemColors.danger, JardemColors.dangerSoft),
      ChipTone.info => (JardemColors.primaryDark, JardemColors.primarySoft),
      ChipTone.neutral => (JardemColors.muted, JardemColors.background),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(label, style: JardemTheme.text(12, FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}
