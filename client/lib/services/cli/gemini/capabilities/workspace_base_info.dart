import '../../registry/capabilities/workspace_base_info_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access.dart';

/// Gemini workspace access.
///
/// The primary workspace is process cwd (set by the launch command builder),
/// exactly as for the other CLIs. No directory launch flag is contributed in
/// this phase: gemini sessions are terminal-less ACP sessions over a single
/// home folder, and the workspace prompt section (same-host extra dirs, remote
/// folders) is inherited from [WorkspaceBaseInfoCapabilityBase] regardless.
final class GeminiWorkspaceBaseInfo extends WorkspaceBaseInfoCapabilityBase {
  const GeminiWorkspaceBaseInfo();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) => const [];
}
