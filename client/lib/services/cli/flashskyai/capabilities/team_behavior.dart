import '../../registry/capabilities/team_behavior_capability.dart';

final class FlashskyaiTeamBehavior implements TeamBehaviorCapability {
  const FlashskyaiTeamBehavior();

  @override
  bool get supportsNativeTeam => true;

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
  bool get usesShellActivity => true;

  @override
  MemberAgentPresetStyle? get agentPresetStyle =>
      MemberAgentPresetStyle.flashskyaiCatalog;
}
