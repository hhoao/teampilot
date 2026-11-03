import '../../../acp/acp_background_liveness.dart';
import '../../../io/filesystem.dart';
import '../cli_capability.dart';

/// Optional ACP capability: the agent leaves on-disk evidence of out-of-turn
/// work that the background watch can poll.
///
/// The ACP wire goes silent after `end_turn`, so a lease armed when a tool call
/// reported `isBackground: true` would otherwise sit until the watch window
/// closes — long after the shell / child agent actually finished. Reading the
/// agent's own metadata clears the signal as soon as the work is really gone.
abstract interface class AcpBackgroundLivenessCapability
    implements CliCapability {
  /// Builds a liveness probe for [sessionId]'s out-of-turn work, or null when
  /// this CLI keeps no evidence the app can read.
  AcpBackgroundLivenessProbe? createBackgroundLivenessProbe({
    required Filesystem fs,
    required String sessionToolDir,
    required String sessionId,
  });
}
