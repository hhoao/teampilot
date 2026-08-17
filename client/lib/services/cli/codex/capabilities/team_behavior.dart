import '../../registry/capabilities/team_behavior_capability.dart';

/// Codex participates in TeamPilot teams through TeamBus/mixed sessions.
/// It has no native team identity arguments to add to a startup command.
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
