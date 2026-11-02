import '../../registry/capabilities/workspace_base_info_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access.dart';

/// Antigravity workspace access.
///
/// ACP launches with the workspace as the process cwd, so no directory flag is
/// contributed. The workspace prompt section (same-host extra dirs and remote
/// folders) is inherited from [WorkspaceBaseInfoCapabilityBase].
final class AntigravityWorkspaceBaseInfo
    extends WorkspaceBaseInfoCapabilityBase {
  const AntigravityWorkspaceBaseInfo();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) => const [];
}
