import '../../../acp/projects_jsonl_background_transcript.dart';
import 'history/compatible_jsonl.dart';

/// Incremental reader for a Claude Agent SDK session transcript.
///
/// `claude-agent-acp` writes `$CLAUDE_CONFIG_DIR/projects/<bucket>/<id>.jsonl`
/// — the same layout the CLI's own `--resume` reads, and the adapter looks the
/// file up by scanning every project bucket (a session may be reopened from a
/// worktree whose bucket differs from the one it was written under). Mirroring
/// that scan keeps the watch working after a worktree move.
final class ClaudeAcpBackgroundTranscriptSource
    extends ProjectsJsonlBackgroundTranscriptSource {
  ClaudeAcpBackgroundTranscriptSource({
    required super.fs,
    required super.sessionToolDir,
    required super.sessionId,
  }) : super(lineAppend: appendClaudeJsonlEvent, fallbackPrefix: 'claude');
}
