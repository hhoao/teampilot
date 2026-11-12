import '../../registry/capabilities/workspace_base_info_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access.dart';

/// Grok workspace access.
///
/// The primary workspace is the process cwd (set by the ACP launch builder).
/// Additional directories are communicated through the workspace prompt
/// section inherited from [WorkspaceBaseInfoCapabilityBase].
final class GrokWorkspaceBaseInfo extends WorkspaceBaseInfoCapabilityBase {
  const GrokWorkspaceBaseInfo();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) => const [];
}
