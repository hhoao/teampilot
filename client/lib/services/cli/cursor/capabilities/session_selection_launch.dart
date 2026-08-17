import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/session_selection_arg_provider.dart';

final class CursorSessionSelectionLaunch extends SessionSelectionArgProvider {
  const CursorSessionSelectionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  ) {
    if (selection.kind == SessionSelectionKind.fixed) {
      throw const CliLaunchCapabilityException(
        cli: CliTool.cursor,
        contributionKey: 'cursor-session-selection',
        reason: 'Cursor supports resuming a session but not fixed session ids.',
        exclusiveGroup: 'cursor-session-selection',
      );
    }

    return [
      CliLaunchArgContribution(
        key: 'cursor-session-selection',
        phase: LaunchArgPhase.session,
        exclusiveGroup: 'cursor-session-selection',
        args: ['--resume', selection.id],
      ),
    ];
  }
}
