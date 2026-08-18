import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/session_selection_arg_provider.dart';

final class OpencodeSessionSelectionLaunch extends SessionSelectionArgProvider {
  const OpencodeSessionSelectionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  ) {
    if (selection.kind == SessionSelectionKind.fixed) {
      throw const CliLaunchCapabilityException(
        cli: CliTool.opencode,
        contributionKey: 'opencode-session-selection',
        reason:
            'OpenCode supports selecting a resumable session but not fixed '
            'session ids.',
        exclusiveGroup: 'opencode-session-selection',
      );
    }

    return [
      CliLaunchArgContribution(
        key: 'opencode-session-selection',
        phase: LaunchArgPhase.session,
        exclusiveGroup: 'opencode-session-selection',
        args: ['--session', selection.id],
      ),
    ];
  }
}
