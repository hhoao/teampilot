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
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return [
        _contribution(const [
          '--dangerously-bypass-approvals-and-sandbox',
          '--dangerously-bypass-hook-trust',
        ], key: 'codex-permission-bypass'),
      ];
    }
    throw _unsupportedPolicy();
  }

  CliLaunchArgContribution _contribution(
    List<String> args, {
    String key = 'codex-permission',
  }) => CliLaunchArgContribution(
    key: key,
    phase: LaunchArgPhase.security,
    exclusiveGroup: 'codex-permission-mode',
    args: args,
  );

  CliLaunchCapabilityException _unsupportedPolicy() =>
      const CliLaunchCapabilityException(
        cli: CliTool.codex,
        contributionKey: 'codex-permission',
        reason: 'Codex does not support this launch security policy tuple.',
        exclusiveGroup: 'codex-permission-mode',
      );
}
