import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/session_selection_arg_provider.dart';

final class ClaudeSessionSelectionLaunch extends SessionSelectionArgProvider {
  const ClaudeSessionSelectionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  ) {
    return [
      CliLaunchArgContribution(
        key: 'claude-session-selection',
        phase: LaunchArgPhase.session,
        exclusiveGroup: 'claude-session-selection',
        args: [
          selection.kind == SessionSelectionKind.resume
              ? '--resume'
              : '--session-id',
          selection.id,
        ],
      ),
    ];
  }
}
