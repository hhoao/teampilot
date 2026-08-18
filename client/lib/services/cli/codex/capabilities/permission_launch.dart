import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CodexPermissionLaunch implements CliLaunchArgProvider {
  const CodexPermissionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final policy = context.launchSecurityPolicy;
    if (policy == LaunchSecurityPolicy.cliDefault) return const [];
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return [
        CliLaunchArgContribution(
          key: 'codex-permission-bypass',
          phase: LaunchArgPhase.security,
          exclusiveGroup: 'codex-permission-mode',
          args: [
            '--dangerously-bypass-approvals-and-sandbox',
            '--dangerously-bypass-hook-trust',
          ],
        ),
      ];
    }

    throw const CliLaunchCapabilityException(
      cli: CliTool.codex,
      contributionKey: 'codex-permission',
      reason: 'Codex does not support this launch security policy tuple.',
      exclusiveGroup: 'codex-permission-mode',
    );
  }
}
