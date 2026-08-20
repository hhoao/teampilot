import '../../../../utils/team/team_member_naming.dart';
import '../../../../models/team_config.dart';
import '../../../session/member_role_provision.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/capabilities/team_behavior_capability.dart';

final class ClaudeTeamBehavior
    implements TeamBehaviorCapability, CliLaunchArgProvider {
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
  bool get defaultForceWaitBeforeStop => false;

  @override
  bool get usesClaudeRoster => true;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle =>
      MemberAgentPresetStyle.claudeAgentType;

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final isNative =
        context.team.teamMode == TeamMode.native &&
        context.nativeAgentTeam != false;
    if (isNative) {
      yield CliLaunchArgContribution(
        key: 'claude-native-team-identity',
        phase: LaunchArgPhase.identity,
        args: [
          '--team-name',
          context.teamName,
          '--agent-name',
          context.memberCliId,
          '--agent-id',
          TeamMemberNaming.cliAgentId(
            memberId: context.memberCliId,
            cliTeamName: context.teamName,
          ),
        ],
      );
    }

    if (context.nativeAgentTeam == false) {
      yield CliLaunchArgContribution(
        key: 'claude-simple-disallowed-tools',
        phase: LaunchArgPhase.behavior,
        args: ['--disallowedTools', 'Agent'],
      );
    }

    if (context.team.teamMode == TeamMode.mixed) {
      final denied = MemberRoleProvision.disallowedToolsForMixedClaude(
        isLead: TeamMemberNaming.isTeamLead(context.member),
      );
      yield CliLaunchArgContribution(
        key: 'claude-mixed-disallowed-tools',
        phase: LaunchArgPhase.behavior,
        args: ['--disallowedTools', ...denied],
      );
    }
  }
}
