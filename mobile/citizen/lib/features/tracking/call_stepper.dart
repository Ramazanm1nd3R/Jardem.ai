import 'package:flutter/material.dart';
import 'package:jardem_core/jardem_core.dart';

/// «Принят → Экипаж выехал → В пути → Прибытие».
class CallStepper extends StatelessWidget {
  const CallStepper({super.key, required this.status, this.color = JardemColors.primary});

  final IncidentStatus status;
  final Color color;

  static const _icons = [
    Icons.check_rounded,
    Icons.local_shipping_rounded,
    Icons.navigation_rounded,
    Icons.flag_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final states = citizenStepper(status);
    return Semantics(
      label: 'Статус вызова: ${citizenStatusTitle(status)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < kCitizenSteps.length; i++)
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 26,
                    child: Row(
                      children: [
                        Expanded(child: _line(i == 0 ? null : states[i] != StepPhase.pending)),
                        _Dot(key: Key('step-$i-${states[i].name}'), state: states[i], icon: _icons[i], color: color),
                        Expanded(
                          child: _line(i == kCitizenSteps.length - 1 ? null : states[i + 1] != StepPhase.pending),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    kCitizenSteps[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JardemTheme.text(
                      10.5,
                      states[i] == StepPhase.active ? FontWeight.w800 : FontWeight.w600,
                      color: switch (states[i]) {
                        StepPhase.active => color,
                        StepPhase.done => JardemColors.navy,
                        StepPhase.pending => JardemColors.faint,
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Connector half; null hides it (before the first / after the last dot).
  Widget _line(bool? filled) =>
      filled == null ? const SizedBox.shrink() : Container(height: 2.5, color: filled ? color : JardemColors.border);
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.state, required this.icon, required this.color});

  final StepPhase state;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pending = state == StepPhase.pending;
    final active = state == StepPhase.active;
    return Container(
      width: active ? 26 : 22,
      height: active ? 26 : 22,
      decoration: BoxDecoration(
        color: pending ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(color: pending ? JardemColors.border : color, width: 2),
        boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 4)] : null,
      ),
      child: Icon(icon, size: 13, color: pending ? JardemColors.faint : Colors.white),
    );
  }
}
