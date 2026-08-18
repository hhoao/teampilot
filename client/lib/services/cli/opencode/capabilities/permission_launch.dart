import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/cli_launch_constraint.dart';
import '../../registry/launch/cli_headless_launch_constraint.dart';
import '../../registry/launch/cli_headless_launch_context.dart';

/// Validates OpenCode's config-backed permission mapping. The actual full
/// access materialization is performed by the provider capability, while
/// this constraint prevents argv assembly from silently accepting policies
/// that OpenCode's config schema cannot express.
final class OpencodePermissionLaunch
    implements CliLaunchConstraint, CliHeadlessLaunchConstraint {
  const OpencodePermissionLaunch();

  @override
  void validateLaunch(CliLaunchContext context) {
    _validate(context.launchSecurityPolicy);
  }

  @override
  void validateHeadlessLaunch(CliHeadlessLaunchContext context) {
    _validate(context.securityPolicy);
  }

  void _validate(LaunchSecurityPolicy policy) {
    if (policy == LaunchSecurityPolicy.cliDefault ||
        policy == LaunchSecurityPolicy.fullAccess)
      return;

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
