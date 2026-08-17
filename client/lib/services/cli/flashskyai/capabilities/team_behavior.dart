import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/capabilities/team_behavior_capability.dart';

final class FlashskyaiTeamBehavior
    implements TeamBehaviorCapability, CliLaunchArgProvider {
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

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final isNative =
        context.team.teamMode == TeamMode.native &&
        context.nativeAgentTeam != false;
    if (isNative) {
      yield CliLaunchArgContribution(
        key: 'flashskyai-native-team-identity',
        phase: LaunchArgPhase.identity,
        args: ['--team', context.teamName, '--member', context.memberCliId],
      );
      final loop = context.team.loop;
      if (loop != null) {
        yield CliLaunchArgContribution(
          key: 'flashskyai-native-team-loop',
          phase: LaunchArgPhase.identity,
          args: ['--loop', loop ? 'true' : 'false'],
        );
      }
    }

    if (context.nativeAgentTeam == false) {
      yield CliLaunchArgContribution(
        key: 'flashskyai-simple-disallowed-tools',
        phase: LaunchArgPhase.behavior,
        args: ['--disallowedTools', 'Agent'],
      );
    }
  }
}
