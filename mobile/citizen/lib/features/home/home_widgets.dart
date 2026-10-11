import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../state/location.dart';

/// «Моё местоположение / <address>» card.
class LocationHeader extends StatelessWidget {
  const LocationHeader({super.key, required this.location});

  final UserLocation location;

  @override
  Widget build(BuildContext context) => JardemCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    radius: 14,
    child: Row(
      children: [
        const Icon(Icons.location_on_outlined, color: JardemColors.navy, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Моё местоположение',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JardemTheme.text(13, FontWeight.w800),
                    ),
                  ),
                  if (location.isDemo) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: JardemColors.warningSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Демо-адрес',
                        style: JardemTheme.text(10, FontWeight.w700, color: JardemColors.warning),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                location.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Dismissible «this is a simulation» banner.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key, required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF7E6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFFFE2A8)),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: JardemTheme.text(11.5, FontWeight.w600, color: const Color(0xFF7A5210), height: 1.3),
            ),
          ),
          IconButton(
            tooltip: 'Скрыть',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFB7791F)),
            onPressed: onClose,
          ),
        ],
      ),
    ),
  );
}

/// One-line warning with an optional action (non-blocking error state).
class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Material(
    color: JardemColors.dangerSoft,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: JardemTheme.text(12, FontWeight.w600, color: const Color(0xFFB02A2A))),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!))
          else
            const SizedBox(height: 40),
        ],
      ),
    ),
  );
}

/// Red «112» button — the real emergency number, always one tap away.
class EmergencyCallButton extends StatelessWidget {
  const EmergencyCallButton({super.key, required this.number, required this.onPressed});

  final String number;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Позвонить $number',
    child: Material(
      color: JardemColors.danger,
      elevation: 3,
      shadowColor: JardemColors.danger.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_rounded, color: Colors.white, size: 16),
              Text(number, style: JardemTheme.text(13, FontWeight.w800, color: Colors.white, height: 1.1)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Traffic index and colour legend, shown while the traffic layer is on.
class TrafficLegend extends StatelessWidget {
  const TrafficLegend({super.key, required this.traffic, required this.onRetry});

  final AsyncValue<TrafficData>? traffic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final data = traffic?.valueOrNull;
    final Widget head;
    if (data != null) {
      head = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: trafficIndexLevel(data.index).color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(trafficIndexLabel(data.index), style: JardemTheme.text(12, FontWeight.w800)),
        ],
      );
    } else if (traffic?.hasError ?? false) {
      head = InkWell(
        onTap: onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 14, color: JardemColors.danger),
            const SizedBox(width: 4),
            Text('Пробки: повторить', style: JardemTheme.text(12, FontWeight.w700, color: JardemColors.danger)),
          ],
        ),
      );
    } else {
      head = Text('Пробки: загрузка…', style: JardemTheme.text(12, FontWeight.w700, color: JardemColors.muted));
    }
    return JardemCard(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          head,
          const SizedBox(height: 3),
          for (final level in const [TrafficLevel.slow, TrafficLevel.jam, TrafficLevel.heavy, TrafficLevel.closed])
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 4,
                    decoration: BoxDecoration(color: level.color, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 6),
                  Text(level.label, style: JardemTheme.text(10.5, FontWeight.w600, color: JardemColors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// «Выберите службу» sheet with the four services and «Другое».
class ServiceSheet extends StatelessWidget {
  const ServiceSheet({super.key, required this.onService, required this.onOther, this.loading = false});

  final ValueChanged<ServiceType> onService;
  final VoidCallback onOther;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      boxShadow: [BoxShadow(color: Color(0x1F1A4B8C), blurRadius: 24, offset: Offset(0, -6))],
    ),
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(child: Text('Выберите службу', style: JardemTheme.text(19, FontWeight.w800))),
              if (loading) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in ServiceType.values)
              Expanded(
                child: _ServiceTile(
                  key: Key('service-${s.id}'),
                  label: s.shortTitle,
                  color: JardemColors.service(s),
                  icon: ServiceIcon(s, size: 19),
                  onTap: () => onService(s),
                ),
              ),
            Expanded(
              child: _ServiceTile(
                key: const Key('service-other'),
                label: 'Другое',
                color: JardemColors.primary,
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
                onTap: onOther,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({super.key, required this.label, required this.color, required this.icon, required this.onTap});

  final String label;
  final Color color;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.lerp(color, Colors.white, 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Color.lerp(color, Colors.white, 0.72)!),
            ),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: icon,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: JardemTheme.text(11.5, FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}
