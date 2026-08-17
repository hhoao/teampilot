import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/session_selection_arg_provider.dart';

final class FlashskyaiSessionSelectionLaunch
    extends SessionSelectionArgProvider {
  const FlashskyaiSessionSelectionLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  ) {
    return [
      CliLaunchArgContribution(
        key: 'flashskyai-session-selection',
        phase: LaunchArgPhase.session,
        exclusiveGroup: 'flashskyai-session-selection',
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
