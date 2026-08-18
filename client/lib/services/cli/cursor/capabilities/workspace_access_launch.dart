import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access_arg_provider.dart';

final class CursorWorkspaceAccessLaunch extends WorkspaceAccessArgProvider {
  const CursorWorkspaceAccessLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) {
    final args = <String>[];
    final workingDirectory = access.workingDirectory;
    if (workingDirectory != null) {
      args.addAll(['--workspace', workingDirectory]);
    }
    for (final directory in access.additionalDirectories) {
      args.addAll(['--add-dir', directory]);
    }

    return [
      CliLaunchArgContribution(
        key: 'cursor-workspace-access',
        phase: LaunchArgPhase.workspace,
        args: args,
      ),
    ];
  }
}
