import 'package:flutter/material.dart';
import 'package:jardem_core/jardem_core.dart';

/// One call in the «Вызовы» / «История» lists.
class IncidentCard extends StatelessWidget {
  const IncidentCard({super.key, required this.incident, this.onTap});

  final Incident incident;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final arrival = timeToArrivalS(
      firstArrivalS: i.firstArrivalS,
      createdAt: i.createdAt,
      arrivedAt: i.reachedAt(IncidentStatus.onScene),
    );
    final String detail;
    if (i.status.isActive && i.status != IncidentStatus.onScene) {
      detail = i.etaS == null ? 'Ожидает экипаж' : 'Прибытие через ${formatDuration(i.etaS)}';
    } else if (arrival != null) {
      detail = 'Время прибытия: ${formatDuration(arrival)}';
    } else {
      detail = i.status == IncidentStatus.cancelled ? 'Экипаж не прибыл' : 'Время прибытия неизвестно';
    }
    return JardemCard(
      key: Key('incident-${i.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServiceBadge(i.service, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        i.categoryTitle.isEmpty ? i.serviceTitle : i.categoryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(15, FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip.incident(i.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '№ ${i.number} · ${i.serviceTitle} · ${formatDateTime(i.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
                ),
                if (i.address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: JardemColors.faint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          i.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JardemTheme.text(12.5, FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 14, color: JardemColors.faint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(detail, style: JardemTheme.text(12.5, FontWeight.w600, color: JardemColors.muted)),
                    ),
                    if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: JardemColors.faint),
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
