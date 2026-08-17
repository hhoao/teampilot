import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/session_selection_arg_provider.dart';

final class CodexSessionSelectionLaunch extends SessionSelectionArgProvider {
  const CodexSessionSelectionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  ) {
    return [
      CliLaunchArgContribution(
        key: 'codex-session-selection',
        phase: LaunchArgPhase.command,
        exclusiveGroup: 'codex-session-selection',
        args: ['resume', selection.id],
      ),
    ];
  }
}
