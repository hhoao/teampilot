import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

final class ClaudePermissionLaunch implements CliLaunchArgProvider {
  const ClaudePermissionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final policy = context.launchSecurityPolicy;
    if (policy == const LaunchSecurityPolicy()) return const [];
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return [
        CliLaunchArgContribution(
          key: 'claude-permission-dangerous',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'claude-permission-mode',
          args: ['--dangerously-skip-permissions'],
        ),
      ];
    }
    if (policy == LaunchSecurityPolicy.askReadOnlyTrusted) {
      return [
        CliLaunchArgContribution(
          key: 'claude-permission-plan',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'claude-permission-mode',
          args: ['--permission-mode', 'plan'],
        ),
      ];
    }
    if (policy == LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted) {
      return [
        CliLaunchArgContribution(
          key: 'claude-permission-accept-edits',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'claude-permission-mode',
          args: ['--permission-mode', 'acceptEdits'],
        ),
      ];
    }
    throw const CliLaunchCapabilityException(
      cli: CliTool.claude,
      contributionKey: 'claude-permission',
      reason: 'Claude does not support this launch security policy tuple.',
      exclusiveGroup: 'claude-permission-mode',
    );
  }
}
