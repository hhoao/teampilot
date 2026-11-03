import 'dart:convert';

import '../../../acp/acp_background_liveness.dart';
import '../../../io/filesystem.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_session_config_dir.dart';

/// Cursor leaves per-session evidence of out-of-turn work under
/// `<sessionToolDir>/home/.cursor/projects/<bucket>/`:
///
/// * `agent-transcripts/<agent session id>/subagents/<child id>.jsonl` — one
///   trace per child agent, closed by a `{"type":"turn_ended"}` record.
/// * `terminals/<id>.txt` — backticked metadata for a background shell, whose
///   frontmatter flips to `status: running` while the process is alive.
///
/// Cursor's ACP adapter never emits a completion frame for either, so this is
/// the only way to drop the "background work running" lease when the work is
/// actually done. A bucket is located by scanning for the one that holds this
/// agent session (same approach as the Claude transcript tail reader): a
/// session may be reopened from a worktree whose bucket differs from the one
/// it was written under.
final class CursorBackgroundLivenessProbe
    implements AcpBackgroundLivenessProbe {
  CursorBackgroundLivenessProbe({
    required Filesystem fs,
    required String sessionToolDir,
    required String sessionId,
    DateTime Function()? now,
    this.staleAfter = const Duration(minutes: 2),
  }) : _fs = fs,
       _sessionToolDir = sessionToolDir,
       _sessionId = sessionId,
       _now = now ?? DateTime.now;

  final Filesystem _fs;
  final String _sessionToolDir;
  final String _sessionId;
  final DateTime Function() _now;

  /// A `status: running` terminal whose metadata has not moved for this long is
  /// treated as a crashed leftover, not live work.
  final Duration staleAfter;

  @override
  Future<AcpBackgroundLiveness> probe({DateTime? since}) async {
    try {
      return await _probe(since);
    } on Object {
      return AcpBackgroundLiveness.unknown;
    }
  }

  Future<AcpBackgroundLiveness> _probe(DateTime? since) async {
    final project = await _locateProjectBucket();
    if (project == null) return AcpBackgroundLiveness.unknown;
    var evidence = false;
    DateTime? newestEvidence;

    final children = await _filesIn(
      _fs.pathContext.join(
        project,
        'agent-transcripts',
        _sessionId,
        'subagents',
      ),
      '.jsonl',
    );
    for (final path in children) {
      final content = await _fs.readString(path);
      // A file that vanished or cannot be read is not proof of completion.
      if (content == null) return AcpBackgroundLiveness.running;
      evidence = true;
      if (!cursorSubagentTranscriptEnded(content)) {
        return AcpBackgroundLiveness.running;
      }
      newestEvidence = _newest(newestEvidence, (await _fs.stat(path)).mtime);
    }

    final terminals = await _filesIn(
      _fs.pathContext.join(project, 'terminals'),
      '.txt',
    );
    for (final path in terminals) {
      final content = await _fs.readString(path);
      if (content == null) continue;
      final stat = await _fs.stat(path);
      evidence = true;
      if (cursorTerminalStillRunning(
        content,
        mtime: stat.mtime,
        now: _now(),
        staleAfter: staleAfter,
      )) {
        return AcpBackgroundLiveness.running;
      }
      newestEvidence = _newest(newestEvidence, stat.mtime);
    }

    // No files at all: this session may simply not have spawned anything the
    // app can see (or Cursor has not written it yet) — say so instead of
    // clearing a lease on an empty directory.
    if (!evidence) return AcpBackgroundLiveness.unknown;
    // Everything we can see has finished, but if none of it moved since the
    // watch armed, it may all belong to an earlier task while this task's
    // first record is still being written. Wait for the next tick instead of
    // releasing too early.
    if (since != null &&
        newestEvidence != null &&
        newestEvidence.isBefore(since.subtract(freshnessGrace))) {
      return AcpBackgroundLiveness.unknown;
    }
    return AcpBackgroundLiveness.idle;
  }

  /// A task launched just before `end_turn` may finish while the agent is still
  /// writing its reply, so evidence this far back still counts as this watch's.
  static const freshnessGrace = Duration(minutes: 1);

  static DateTime? _newest(DateTime? current, DateTime? candidate) {
    if (candidate == null) return current;
    if (current == null) return candidate;
    return candidate.isAfter(current) ? candidate : current;
  }

  /// The project bucket that owns this agent session's transcripts.
  Future<String?> _locateProjectBucket() async {
    final ctx = _fs.pathContext;
    final projects = ctx.join(
      _sessionToolDir,
      CursorSessionConfigDir.homeSegment,
      CursorHomeLayout.cursorDirName,
      'projects',
    );
    final List<FsDirEntry> entries;
    try {
      entries = await _fs.listDir(projects);
    } on Object {
      return null;
    }
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final candidate = ctx.join(projects, entry.name);
      final stat = await _fs.stat(
        ctx.join(candidate, 'agent-transcripts', _sessionId),
      );
      if (stat.isDirectory) return candidate;
    }
    return null;
  }

  Future<List<String>> _filesIn(String dir, String extension) async {
    final List<FsDirEntry> entries;
    try {
      entries = await _fs.listDir(dir);
    } on Object {
      return const [];
    }
    final ctx = _fs.pathContext;
    return [
      for (final entry in entries)
        if (!entry.isDirectory && entry.name.endsWith(extension))
          ctx.join(dir, entry.name),
    ];
  }
}

/// Whether a child-agent transcript has closed its turn.
///
/// Every Cursor child appends `{"type":"turn_ended","status":...}` as its last
/// record. An empty or half-written file counts as still running.
bool cursorSubagentTranscriptEnded(String content) {
  final trimmed = content.trimRight();
  if (trimmed.isEmpty) return false;
  final lastLine = trimmed.substring(trimmed.lastIndexOf('\n') + 1);
  final Object? decoded;
  try {
    decoded = jsonDecode(lastLine);
  } on FormatException {
    return false;
  }
  return decoded is Map && decoded['type'] == 'turn_ended';
}

/// Whether a Cursor terminal metadata file reports a live process.
///
/// The frontmatter carries `status: running | succeeded | failed | aborted`.
/// A `running` line older than [staleAfter] is a leftover from a crash, not
/// live work.
bool cursorTerminalStillRunning(
  String content, {
  required DateTime now,
  DateTime? mtime,
  Duration staleAfter = const Duration(minutes: 2),
}) {
  final status = _frontmatterValue(content, 'status');
  if (status != 'running') return false;
  if (mtime == null) return true;
  return now.difference(mtime) <= staleAfter;
}

/// Reads one `key: value` line out of a leading `---` frontmatter block.
String? _frontmatterValue(String content, String key) {
  final lines = const LineSplitter().convert(content);
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  for (final line in lines.skip(1)) {
    final trimmed = line.trim();
    if (trimmed == '---') return null;
    if (!trimmed.startsWith('$key:')) continue;
    final value = trimmed.substring(key.length + 1).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}
