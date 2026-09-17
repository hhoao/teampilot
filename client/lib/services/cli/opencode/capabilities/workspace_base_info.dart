import '../../registry/capabilities/workspace_base_info_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access.dart';

final class OpencodeWorkspaceBaseInfo extends WorkspaceBaseInfoCapabilityBase {
  const OpencodeWorkspaceBaseInfo();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    return const [];
  }

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) => const [];
}
