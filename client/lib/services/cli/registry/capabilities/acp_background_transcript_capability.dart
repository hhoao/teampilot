import '../../../acp/acp_background_transcript.dart';
import '../../../io/filesystem.dart';
import '../cli_capability.dart';

/// Optional ACP capability: the agent keeps a readable on-disk transcript that
/// can be tailed while out-of-turn background work runs.
///
/// The ACP wire goes silent after `end_turn`, so the chat layer otherwise has
/// to replay the whole session through `session/load` to notice that the agent
/// resumed. A CLI that can name its own transcript lets the watch read only
/// the appended records instead.
abstract interface class AcpBackgroundTranscriptCapability
    implements CliCapability {
  /// Builds an incremental reader for [sessionId]'s transcript under
  /// [sessionToolDir] (the CLI's isolated config dir), or null when this CLI
  /// has no transcript layout the app can read.
  AcpBackgroundTranscriptSource? createBackgroundTranscriptSource({
    required Filesystem fs,
    required String sessionToolDir,
    required String sessionId,
  });
}
