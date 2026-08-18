import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

/// Validates OpenCode's security policy boundary.
///
/// OpenCode has no permission/security launch argv that maps the normalized
/// policy dimensions. Its current permissive defaults, together with the
/// existing session-home config materialization for external directories,
/// explicitly cover [LaunchSecurityPolicy.fullAccess]; OpenCode has no
/// separate hook-trust gate to bypass. Other policy tuples must fail instead
/// of silently falling back to OpenCode defaults.
final class OpencodePermissionLaunch implements CliLaunchArgProvider {
  const OpencodePermissionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final policy = context.launchSecurityPolicy;
    if (policy == const LaunchSecurityPolicy() ||
        policy == LaunchSecurityPolicy.fullAccess) {
      return const [];
    }

    throw const CliLaunchCapabilityException(
      cli: CliTool.opencode,
      contributionKey: 'opencode-permission',
      reason:
          'OpenCode cannot represent this launch security policy through its '
          'current CLI/config capabilities.',
      exclusiveGroup: 'opencode-permission-mode',
    );
  }
}
