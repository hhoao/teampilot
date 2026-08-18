import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CursorPermissionLaunch implements CliLaunchArgProvider {
  const CursorPermissionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final policy = context.launchSecurityPolicy;
    if (policy == LaunchSecurityPolicy.cliDefault) return const [];
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return [
        CliLaunchArgContribution(
          key: 'cursor-permission-force',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'cursor-permission-mode',
          args: ['--force'],
        ),
      ];
    }

    throw const CliLaunchCapabilityException(
      cli: CliTool.cursor,
      contributionKey: 'cursor-permission',
      reason: 'Cursor does not support this launch security policy tuple.',
      exclusiveGroup: 'cursor-permission-mode',
    );
  }
}
