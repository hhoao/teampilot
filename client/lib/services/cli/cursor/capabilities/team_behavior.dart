import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/capabilities/team_behavior_capability.dart';

final class CursorTeamBehavior
    implements TeamBehaviorCapability, CliLaunchArgProvider {
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

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    if (context.team.teamMode == TeamMode.mixed) {
      yield CliLaunchArgContribution(
        key: 'cursor-mixed-approve-mcps',
        phase: LaunchArgPhase.behavior,
        args: ['--approve-mcps'],
      );
    }
  }
}
