import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../logic/steps.dart';
import '../state/crew.dart';
import 'widgets.dart';

/// One button of the crew state machine. Performs the step, shows a spinner
/// while the request runs and explains a failure (409 → why) in a snackbar.
class StepButton extends ConsumerStatefulWidget {
  const StepButton(this.step, {super.key, required this.service, this.buttonKey, this.height = 52});

  final CrewStep step;
  final ServiceType service;

  /// Defaults to `Key('step-<name>')`.
  final Key? buttonKey;
  final double height;

  @override
  ConsumerState<StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends ConsumerState<StepButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await ref.read(crewProvider.notifier).perform(widget.step);
    } catch (e) {
      toast(messenger, stepErrorMessage(e, widget.step));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static IconData _icon(CrewStep step) => switch (step) {
    CrewStep.goOnDuty => Icons.play_arrow_rounded,
    CrewStep.endShift => Icons.logout_rounded,
    CrewStep.accept => Icons.check_circle_rounded,
    CrewStep.arrive => Icons.flag_rounded,
    CrewStep.transport => Icons.airline_seat_flat_rounded,
    CrewStep.complete => Icons.task_alt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final key = widget.buttonKey ?? Key('step-${step.name}');
    final label = stepLabel(step, widget.service);
    if (!isPrimaryStep(step)) {
      return SecondaryButton(
        key: key,
        label: label,
        icon: _icon(step),
        color: JardemColors.muted,
        height: widget.height,
        onPressed: _busy ? null : _run,
      );
    }
    return PrimaryButton(
      key: key,
      label: label,
      icon: _icon(step),
      loading: _busy,
      height: widget.height,
      radius: 16,
      color: step == CrewStep.complete ? JardemColors.success : JardemColors.primary,
      onPressed: _run,
    );
  }
}

/// All buttons for the crew's current status, stacked.
class StepButtons extends ConsumerWidget {
  const StepButtons({super.key, this.includeShift = true});

  /// False hides «Выйти на смену» / «Завершить смену» (navigation, call card).
  final bool includeShift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crew = ref.watch(crewProvider);
    final unit = crew.unit;
    if (unit == null) return const SizedBox.shrink();
    final steps = [
      for (final s in nextSteps(crew.status, unit.service))
        if (includeShift || s.action != null) s,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          StepButton(steps[i], service: unit.service),
        ],
      ],
    );
  }
}
