import 'package:ai_message_core/ai_message_core.dart';

import '../../../acp/acp_background_transcript.dart';
import '../../../chat/conversation/history/ai_transcript_tail_reader.dart';
import '../../../io/filesystem.dart';
import 'history/compatible_jsonl.dart';

/// Incremental reader for a Claude Agent SDK session transcript.
///
/// `claude-agent-acp` writes `$CLAUDE_CONFIG_DIR/projects/<bucket>/<id>.jsonl`
/// — the same layout the CLI's own `--resume` reads, and the adapter looks the
/// file up by scanning every project bucket (a session may be reopened from a
/// worktree whose bucket differs from the one it was written under). Mirroring
/// that scan keeps the watch working after a worktree move.
///
/// Reading goes through [AiTranscriptTailReader], so only appended bytes are
/// parsed after the first read, and a compacted / rewritten file falls back to
/// a full parse instead of producing a wrong tail.
final class ClaudeAcpBackgroundTranscriptSource
    implements AcpBackgroundTranscriptSource {
  ClaudeAcpBackgroundTranscriptSource({
    required Filesystem fs,
    required String sessionToolDir,
    required String sessionId,
  }) : _fs = fs,
       _sessionToolDir = sessionToolDir,
       _sessionId = sessionId;

  final Filesystem _fs;
  final String _sessionToolDir;
  final String _sessionId;

  final TailReaderState _state = TailReaderState();
  final AiTranscriptTailReader _reader = AiTranscriptTailReader(
    lineAppend: appendClaudeJsonlEvent,
    fallbackPrefix: 'claude',
  );

  String? _path;

  @override
  Future<AcpBackgroundTranscriptResult?> refresh() async {
    var path = await _locate();
    if (path != null) {
      final stat = await _fs.stat(path);
      if (!stat.isFile) {
        // The session moved to another project bucket (worktree move): the
        // adapter's own lookup re-scans every read for the same reason.
        _path = null;
        path = await _locate();
      }
    }
    if (path == null) return null;
    final result = await _reader.refresh(fs: _fs, path: path, state: _state);
    if (!result.changed) return AcpBackgroundTranscriptResult.unchanged;
    return AcpBackgroundTranscriptResult(
      changed: true,
      messages: List<AiMessage>.unmodifiable(_state.messages),
    );
  }

  /// The transcript path, cached once found. A miss is retried on the next
  /// read: a freshly created session may not have written its first record
  /// when the initial reconcile runs.
  Future<String?> _locate() async {
    final cached = _path;
    if (cached != null) return cached;

    final projects = _fs.pathContext.join(_sessionToolDir, 'projects');
    final List<FsDirEntry> entries;
    try {
      entries = await _fs.listDir(projects);
    } on Object {
      return null;
    }
    final fileName = '$_sessionId.jsonl';
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final candidate = _fs.pathContext.join(projects, entry.name, fileName);
      final stat = await _fs.stat(candidate);
      if (!stat.isFile) continue;
      _path = candidate;
      return candidate;
    }
    return null;
  }
}
