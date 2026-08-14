import '../../registry/capabilities/team_behavior_capability.dart';

final class ClaudeTeamBehavior implements TeamBehaviorCapability {
  const ClaudeTeamBehavior();

  @override
  bool get supportsNativeTeam => true;

  @override
  bool get longBlockingWaitForMessage => true;

  @override
  bool get supportsLocalStdioBridge => true;

  @override
  Set<String> get doneEventNames => const {'Stop', 'StopFailure'};

  @override
  bool get requiresPtyFallback => false;

  @override
  bool get usesDoorbellPush => false;

  @override
  bool get defaultForceWaitBeforeStop => true;

  @override
  bool get usesClaudeRoster => true;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle =>
      MemberAgentPresetStyle.claudeAgentType;
}
