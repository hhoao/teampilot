import '../../registry/capabilities/team_behavior_capability.dart';

final class CursorTeamBehavior implements TeamBehaviorCapability {
  const CursorTeamBehavior();

  @override
  bool get supportsNativeTeam => false;

  @override
  bool get longBlockingWaitForMessage => false;

  @override
  bool get supportsLocalStdioBridge => false;

  @override
  Set<String> get doneEventNames => const {'stop'};

  @override
  bool get requiresPtyFallback => true;

  @override
  bool get usesDoorbellPush => true;

  @override
  bool get defaultForceWaitBeforeStop => false;

  @override
  bool get usesClaudeRoster => false;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}
