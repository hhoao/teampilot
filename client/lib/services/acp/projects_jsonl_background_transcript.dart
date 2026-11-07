import 'package:ai_message_core/ai_message_core.dart';

import '../chat/conversation/history/ai_transcript_tail_reader.dart';
import '../cli/registry/capabilities/ai_history_capability.dart';
import '../io/filesystem.dart';
import 'acp_background_transcript.dart';

/// Incremental reader for an agent transcript laid out as
/// `<sessionToolDir>/projects/<bucket>/<sessionId>.jsonl`.
///
/// Claude Code (through `claude-agent-acp`) and Qoder both write this layout:
/// one JSONL file per agent session, grouped by a slug of the working
/// directory. A session may be reopened from a worktree whose bucket differs
/// from the one it was written under, so the file is looked up by scanning
/// every bucket (matching the adapters' own resume lookup).
///
/// Reading goes through [AiTranscriptTailReader], so only appended bytes are
/// parsed after the first read, and a compacted / rewritten file falls back to
/// a full parse instead of producing a wrong tail.
class ProjectsJsonlBackgroundTranscriptSource
    implements AcpBackgroundTranscriptSource {
  ProjectsJsonlBackgroundTranscriptSource({
    required Filesystem fs,
    required String sessionToolDir,
    required String sessionId,
    required AiTranscriptLineAppend lineAppend,
    required String fallbackPrefix,
  }) : _fs = fs,
       _sessionToolDir = sessionToolDir,
       _sessionId = sessionId,
       _reader = AiTranscriptTailReader(
         lineAppend: lineAppend,
         fallbackPrefix: fallbackPrefix,
       );

  final Filesystem _fs;
  final String _sessionToolDir;
  final String _sessionId;
  final AiTranscriptTailReader _reader;

  final TailReaderState _state = TailReaderState();

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
