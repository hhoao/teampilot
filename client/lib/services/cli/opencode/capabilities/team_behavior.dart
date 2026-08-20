import '../../registry/capabilities/team_behavior_capability.dart';

final class OpencodeTeamBehavior implements TeamBehaviorCapability {
  const OpencodeTeamBehavior();

  @override
  bool get supportsNativeTeam => false;

  @override
  bool get longBlockingWaitForMessage => true;

  @override
  bool get supportsLocalStdioBridge => false;

  @override
  Set<String> get doneEventNames => const {'session.idle'};

  @override
  bool get requiresPtyFallback => false;

  @override
  bool get usesDoorbellPush => false;

  @override
  bool get defaultForceWaitBeforeStop => false;

  @override
  bool get usesClaudeRoster => false;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}
