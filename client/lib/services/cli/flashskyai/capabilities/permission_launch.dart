import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

final class FlashskyaiPermissionLaunch implements CliLaunchArgProvider {
  const FlashskyaiPermissionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final policy = context.launchSecurityPolicy;
    if (policy == LaunchSecurityPolicy.cliDefault) return const [];
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return [
        CliLaunchArgContribution(
          key: 'flashskyai-permission-dangerous',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'flashskyai-permission-mode',
          args: ['--dangerously-skip-permissions'],
        ),
      ];
    }
    if (policy == LaunchSecurityPolicy.askReadOnlyTrusted) {
      return [
        CliLaunchArgContribution(
          key: 'flashskyai-permission-plan',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'flashskyai-permission-mode',
          args: ['--permission-mode', 'plan'],
        ),
      ];
    }
    if (policy == LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted) {
      return [
        CliLaunchArgContribution(
          key: 'flashskyai-permission-accept-edits',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'flashskyai-permission-mode',
          args: ['--permission-mode', 'acceptEdits'],
        ),
      ];
    }
    throw const CliLaunchCapabilityException(
      cli: CliTool.flashskyai,
      contributionKey: 'flashskyai-permission',
      reason: 'FlashskyAI does not support this launch security policy tuple.',
      exclusiveGroup: 'flashskyai-permission-mode',
    );
  }
}
