import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access_arg_provider.dart';

final class ClaudeWorkspaceAccessLaunch extends WorkspaceAccessArgProvider {
  const ClaudeWorkspaceAccessLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) {
    // Claude Code has no `--dir`. The primary workspace is process cwd
    // (set by TerminalSession / LaunchCommandBuilder). `--add-dir` is only
    // for additional directories.
    if (access.additionalDirectories.isEmpty) {
      return const [];
    }
    final args = <String>[
      for (final directory in access.additionalDirectories) ...[
        '--add-dir',
        directory,
      ],
    ];
    return [
      CliLaunchArgContribution(
        key: 'claude-workspace-access',
        phase: LaunchArgPhase.workspace,
        args: args,
      ),
    ];
  }
}
