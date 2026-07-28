import '../cli_capability.dart';

final class TurnInterruptPlan {
  const TurnInterruptPlan({
    required this.steps,
    this.gapBetweenSteps = Duration.zero,
  });

  final List<String> steps;
  final Duration gapBetweenSteps;
}

abstract interface class TurnInterruptCapability implements CliCapability {
  bool get supportsTurnInterrupt;
  TurnInterruptPlan get interruptPlan;
}

/// Default v1 plan: Ctrl+C once.
final class CtrlCTurnInterrupt implements TurnInterruptCapability {
  const CtrlCTurnInterrupt();

  @override
  bool get supportsTurnInterrupt => true;

  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
}
