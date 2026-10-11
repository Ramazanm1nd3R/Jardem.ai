import 'package:flutter/material.dart';
import 'package:jardem_core/jardem_core.dart';

/// Compact card with what the text triage understood.
class TriageHint extends StatelessWidget {
  const TriageHint({
    super.key,
    required this.triage,
    required this.catalog,
    required this.currentService,
    required this.currentCategory,
    required this.onSwitch,
  });

  final TriageResult triage;
  final List<ServiceInfo> catalog;
  final ServiceType currentService;
  final String? currentCategory;

  /// One-tap «Сменить на: …» — called with the suggested service and category.
  final void Function(ServiceType service, String category) onSwitch;

  @override
  Widget build(BuildContext context) {
    final suggestedService = triage.service;
    final suggested = triage.category;
    final info = suggestedService == null ? null : catalog.where((s) => s.service == suggestedService).firstOrNull;
    final title = triage.categoryTitle ?? info?.category(suggested)?.title ?? suggested;
    final differs = triage.hasSuggestion && (suggestedService != currentService || suggested != currentCategory);
    final critical = triage.priority == 1 || triage.lifeThreat;
    final accent = critical ? JardemColors.danger : JardemColors.primary;
    final missing = triage.missing.map(missingLabel).toList();

    return Container(
      key: const Key('triage-hint'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.lerp(accent, Colors.white, 0.93),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color.lerp(accent, Colors.white, 0.7)!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  triage.uncertain || title == null
                      ? 'Не удалось определить категорию по описанию'
                      : 'Похоже на: ${info?.title ?? ''}${info == null ? '' : ' · '}$title',
                  style: JardemTheme.text(13, FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              StatusChip(priorityLabel(triage.priority), tone: critical ? ChipTone.danger : ChipTone.info),
            ],
          ),
          if (triage.lifeThreat) ...[
            const SizedBox(height: 6),
            Text(
              'Указана угроза жизни — вызов получит высший приоритет.',
              style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.danger),
            ),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Уточните: ${missing.join(', ')}',
              style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.3),
            ),
          ],
          if (differs && title != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                key: const Key('triage-switch'),
                onPressed: () => onSwitch(suggestedService!, suggested!),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text('Сменить на: $title'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: accent),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: JardemTheme.text(12.5, FontWeight.w700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
