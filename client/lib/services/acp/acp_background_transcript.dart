import 'package:ai_message_core/ai_message_core.dart';

/// One incremental read of the agent's own on-disk transcript.
///
/// The ACP protocol drops `session/update` frames once a prompt resolves, so
/// out-of-turn work (background shell tasks) can only be observed by reading
/// what the agent writes itself. [changed] is false when the file has not
/// moved since the previous read; [messages] is then the previous snapshot.
class AcpBackgroundTranscriptResult {
  const AcpBackgroundTranscriptResult({
    required this.changed,
    required this.messages,
  });

  /// Whether the transcript grew / was rewritten since the previous read.
  final bool changed;

  /// The full parsed transcript after this read.
  final List<AiMessage> messages;

  static const unchanged = AcpBackgroundTranscriptResult(
    changed: false,
    messages: [],
  );
}

/// Incremental source for one ACP session's agent-side transcript.
///
/// Implementations read only what was appended since the previous call, so the
/// out-of-turn watch costs a token check instead of a full history replay.
abstract interface class AcpBackgroundTranscriptSource {
  /// Reads the transcript, or returns null when this session has no readable
  /// transcript (the caller then falls back to protocol reconciliation).
  Future<AcpBackgroundTranscriptResult?> refresh();
}

/// Builds a source for an agent session that only becomes known after the
/// agent's `session/new` / `session/load` response.
typedef AcpBackgroundTranscriptSourceFactory =
    AcpBackgroundTranscriptSource? Function({
      required String sessionToolDir,
      required String sessionId,
    });
