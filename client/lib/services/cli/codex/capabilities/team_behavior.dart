import '../../registry/capabilities/team_behavior_capability.dart';

final class CodexTeamBehavior implements TeamBehaviorCapability {
  const CodexTeamBehavior();

  @override
  bool get supportsNativeTeam => false;

  @override
  bool get longBlockingWaitForMessage => true;

  @override
  bool get supportsLocalStdioBridge => false;

  @override
  Set<String> get doneEventNames => const {'Stop', 'StopFailure'};

  @override
  bool get requiresPtyFallback => false;

  @override
  bool get usesDoorbellPush => false;

  @override
  bool get defaultForceWaitBeforeStop => true;

  @override
  bool get usesClaudeRoster => false;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}
