import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';

import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import '../../../../session/subagent_side_transcript_path.dart';
import 'claude_compatible_jsonl.dart';
import 'subagent_side_resolver.dart';

/// True for the Claude `Workflow` orchestration tool across casing variants
/// (`Workflow`, `workflow`, `work_flow`).
bool isWorkflowTool(String? toolName) {
  if (toolName == null || toolName.isEmpty) return false;
  final compact = toolName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  return compact == 'workflow';
}

/// Resolves a Claude Code `Workflow` tool call into its run record plus one
/// [SubagentWorkflowAgent] per spawned sub-agent.
///
/// Deterministic mapping (verified on real sessions):
/// ```
/// Workflow tool_use id
///   → <task-notification><tool-use-id>…</tool-use-id><task-id>…</task-id>
///     in the parent transcript
///   → run record `{parentStem}/workflows/wf_{runId}.json[taskId]`
///   → run dir `{parentStem}/subagents/workflows/wf_{runId}/agent-*.jsonl`
/// ```
/// A run that never materialized (cancelled / stopped immediately) has no
/// `taskId` notification or no agent transcripts — [resolve] returns null and
/// the inflater falls back to the tool result.
///
/// ## Incremental resolution
///
/// The history loader re-inflates subagent attachments on every live refresh
/// (cache token = parent transcript mtime, which changes on each append while
/// a workflow runs). To avoid re-reading + re-parsing everything every ~750ms,
/// this resolver memoizes per parent transcript path:
///
///   * the `<task-notification>` index and run-record index — rebuilt only when
///     the parent transcript changes;
///   * per-agent parsed transcripts, validated by file (mtime, size) — a run
///     that has not changed is reused instead of re-parsed, so a live run only
///     pays for agents that actually grew.
///
/// [clearWorkflowCache] releases the memo (and is called by tests).
final class ClaudeWorkflowResolver {
  const ClaudeWorkflowResolver();

  static const int _maxCachedParents = 4;
  static final Map<String, _WorkflowCache> _byParent = {};
  static final List<String> _lru = <String>[];

  @visibleForTesting
  static void clearWorkflowCache() {
    _byParent.clear();
    _lru.clear();
  }

  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required String? parentTranscriptPath,
  }) async {
    final parentPath = _trimmed(parentTranscriptPath);
    if (parentPath == null) return null;
    if (part.toolCallId.trim().isEmpty) return null;

    final cache = await _entryFor(ctx, parentPath);
    final taskId = cache.taskNotifications[part.toolCallId];
    if (taskId == null) return null;

    final runRecord = cache.runRecords[taskId];
    if (runRecord == null) return null;

    final runId = _trimmed(runRecord['runId']);
    if (runId == null) return null;

    final agents = await _agentsFor(
      ctx,
      cache,
      parentPath,
      runId,
      part.toolCallId,
    );

    final info = SubagentWorkflowInfo(
      runId: runId,
      workflowName: _trimmed(runRecord['workflowName']),
      status: _trimmed(runRecord['status']),
      phases: _stringList(runRecord['phases']),
      agentCount: _intValue(runRecord['agentCount']) ?? agents.length,
      summary: _trimmed(runRecord['summary']),
      duration: _durationMs(runRecord['durationMs']),
      agents: agents,
    );

    final runDir = claudeWorkflowRunDirFor(parentPath, runId: runId);
    return SubagentSideResolveResult(
      messages: _synthesizeRunSummary(runRecord),
      handle: SubagentFileHandle(runDir),
      workflow: info,
    );
  }

  /// Returns the per-parent cache, rebuilding the notification/run-record
  /// indexes only when the parent transcript changed, and carrying over the
  /// per-agent caches (each still validated by mtime on reuse).
  static Future<_WorkflowCache> _entryFor(
    SessionHistoryContext ctx,
    String parentPath,
  ) async {
    _lru.remove(parentPath);
    _lru.add(parentPath);

    final stat = await ctx.fs.stat(parentPath);
    final key = _statKey(stat);
    final existing = _byParent[parentPath];
    if (existing != null && existing.key != null && existing.key == key) {
      return existing;
    }

    final previous = existing;
    final content = await ctx.fs.readString(parentPath);
    final entry = _WorkflowCache(
      key: key,
      taskNotifications: content == null
          ? const {}
          : _taskNotifications(content),
      runRecords: await _scanRunRecords(ctx, parentPath),
    );
    if (previous != null) {
      entry.agentsByPath.addAll(previous.agentsByPath);
      entry.journalByPath.addAll(previous.journalByPath);
    }
    _byParent[parentPath] = entry;
    _evictIfNeeded();
    return entry;
  }

  static void _evictIfNeeded() {
    while (_byParent.length > _maxCachedParents && _lru.isNotEmpty) {
      final oldest = _lru.removeAt(0);
      _byParent.remove(oldest);
    }
  }

  static String? _statKey(FsStat stat) {
    final mtime = stat.mtime;
    if (mtime == null) return null;
    return '${mtime.toUtc().toIso8601String()}:${stat.size ?? -1}';
  }

  static Map<String, String> _taskNotifications(String content) {
    final out = <String, String>{};
    final notif = RegExp(r'<task-notification>([\s\S]*?)</task-notification>');
    final taskId = RegExp(r'<task-id>([^<]+)</task-id>');
    final toolUse = RegExp(r'<tool-use-id>([^<]+)</tool-use-id>');
    for (final m in notif.allMatches(content)) {
      final body = m.group(1) ?? '';
      final tu = toolUse.firstMatch(body)?.group(1)?.trim();
      final ti = taskId.firstMatch(body)?.group(1)?.trim();
      if (tu == null || tu.isEmpty || ti == null || ti.isEmpty) continue;
      out[tu] = ti;
    }
    return out;
  }

  /// Indexes every run record `workflows/wf_*.json` by its `taskId`.
  static Future<Map<String, Map<String, Object?>>> _scanRunRecords(
    SessionHistoryContext ctx,
    String parentPath,
  ) async {
    final out = <String, Map<String, Object?>>{};
    final workflowsDir = claudeWorkflowsDirFor(parentPath);
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDir(workflowsDir);
    } catch (_) {
      return out;
    }
    for (final entry in entries) {
      if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
      final content = await ctx.fs.readString(
        ctx.fs.pathContext.join(workflowsDir, entry.name),
      );
      if (content == null) continue;
      final decoded = _tryDecodeObject(content);
      if (decoded == null) continue;
      final taskId = _trimmed(decoded['taskId']);
      if (taskId == null) continue;
      out[taskId] = decoded;
    }
    return out;
  }

  Future<List<SubagentWorkflowAgent>> _agentsFor(
    SessionHistoryContext ctx,
    _WorkflowCache cache,
    String parentPath,
    String runId,
    String parentToolCallId,
  ) async {
    final runDir = claudeWorkflowRunDirFor(parentPath, runId: runId);
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDir(runDir);
    } catch (_) {
      return const [];
    }

    final journal = await _journalFor(ctx, cache, runDir);
    final path = ctx.fs.pathContext;
    final agents = <SubagentWorkflowAgent>[];
    for (final entry in entries) {
      final name = entry.name;
      if (entry.isDirectory ||
          !name.startsWith('agent-') ||
          !name.endsWith('.jsonl')) {
        continue;
      }
      final agentId =
          name.substring('agent-'.length, name.length - '.jsonl'.length);
      if (agentId.isEmpty) continue;

      final filePath = path.join(runDir, name);
      final agent = await _agentFor(
        ctx,
        cache,
        filePath,
        agentId,
        parentToolCallId,
        journal,
      );
      if (agent != null) agents.add(agent);
    }
    agents.sort(
      (a, b) =>
          (journal[a.agentId]?.order ?? 0).compareTo(
            journal[b.agentId]?.order ?? 0,
          ),
    );
    return agents;
  }

  /// Parses one agent transcript unless the file is unchanged since it was
  /// last parsed (validated by mtime + size).
  Future<SubagentWorkflowAgent?> _agentFor(
    SessionHistoryContext ctx,
    _WorkflowCache cache,
    String filePath,
    String agentId,
    String parentToolCallId,
    Map<String, _AgentJournal> journal,
  ) async {
    final stat = await ctx.fs.stat(filePath);
    final key = _statKey(stat);
    final cached = cache.agentsByPath[filePath];
    if (key != null && cached != null && cached.key == key) {
      return cached.agent;
    }

    final content = await ctx.fs.readString(filePath);
    if (content == null) return null;
    final messages = parseClaudeCompatibleJsonl(
      content,
      fallbackId: () => 'workflow-agent-$agentId-$parentToolCallId',
    );
    final j = journal[agentId];
    final agent = SubagentWorkflowAgent(
      agentId: agentId,
      role: _roleFromFirstUser(messages),
      status: j?.status,
      messages: messages,
      handle: SubagentFileHandle(filePath),
    );
    cache.agentsByPath[filePath] = _CachedAgent(key: key, agent: agent);
    return agent;
  }

  Future<Map<String, _AgentJournal>> _journalFor(
    SessionHistoryContext ctx,
    _WorkflowCache cache,
    String runDir,
  ) async {
    final journalPath = ctx.fs.pathContext.join(runDir, 'journal.jsonl');
    final stat = await ctx.fs.stat(journalPath);
    final key = _statKey(stat);
    final cached = cache.journalByPath[journalPath];
    if (key != null && cached != null && cached.key == key) {
      return cached.map;
    }
    final map = await _readJournal(ctx, runDir);
    cache.journalByPath[journalPath] = _CachedJournal(key: key, map: map);
    return map;
  }

  /// Journal lines: `{"type":"started"|"result","agentId":…,"result":{…}}`.
  /// Keeps the last result per agent plus its first-seen order.
  static Future<Map<String, _AgentJournal>> _readJournal(
    SessionHistoryContext ctx,
    String runDir,
  ) async {
    final out = <String, _AgentJournal>{};
    final content = await ctx.fs.readString(
      ctx.fs.pathContext.join(runDir, 'journal.jsonl'),
    );
    if (content == null) return out;
    var order = 0;
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final decoded = _tryDecodeObject(trimmed);
      if (decoded == null) continue;
      final agentId = _trimmed(decoded['agentId']);
      if (agentId == null) continue;

      final current = out[agentId] ?? _AgentJournal(order: order);
      if (decoded['type'] == 'result') {
        final result = decoded['result'];
        if (result is Map) {
          final status = _trimmed(result['status']);
          final approved = result['approved'];
          current.status = status ??
              (approved is bool && approved ? 'approved' : null);
          current.summary = _trimmed(result['summary']) ??
              _trimmed(result['notes']) ??
              current.summary;
        }
      }
      out[agentId] = current;
      order++;
    }
    return out;
  }

  static String? _roleFromFirstUser(List<AiMessage> messages) {
    for (final message in messages) {
      if (message.role != AiRole.user) continue;
      for (final part in message.parts) {
        if (part is AiTextPart) {
          final text = part.text.trim();
          if (text.isEmpty) continue;
          final line = text.split('\n').first.trim();
          final stripped = line.replaceFirst(
            RegExp(r'^You are (the )?', caseSensitive: false),
            '',
          ).trim();
          return stripped.isEmpty ? null : stripped;
        }
      }
    }
    return null;
  }

  static List<AiMessage> _synthesizeRunSummary(
    Map<String, Object?> runRecord,
  ) {
    final summary = _trimmed(runRecord['summary']) ??
        _nestedSummary(runRecord['result']);
    if (summary == null || summary.isEmpty) return const [];
    return [
      AiMessage(
        id: 'workflow-summary-${_trimmed(runRecord['runId']) ?? 'run'}',
        role: AiRole.assistant,
        parts: [AiTextPart(text: summary)],
      ),
    ];
  }

  static String? _nestedSummary(Object? result) {
    if (result is! Map) return null;
    return _trimmed(result['summary']);
  }

  static Map<String, Object?>? _tryDecodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  static String? _trimmed(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return [
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    }
    if (value is String) {
      return [
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    return const [];
  }

  static int? _intValue(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Duration? _durationMs(Object? value) {
    final ms = _intValue(value);
    if (ms == null) return null;
    return Duration(milliseconds: ms);
  }
}

class _WorkflowCache {
  _WorkflowCache({
    required this.key,
    required this.taskNotifications,
    required this.runRecords,
  });

  /// Parent transcript (mtime, size); null when unkeyable (never reused).
  final String? key;
  final Map<String, String> taskNotifications;
  final Map<String, Map<String, Object?>> runRecords;

  /// Parsed agent transcripts by file path, validated by (mtime, size).
  final Map<String, _CachedAgent> agentsByPath = {};

  /// Parsed per-run journals by journal file path.
  final Map<String, _CachedJournal> journalByPath = {};
}

class _CachedAgent {
  _CachedAgent({required this.key, required this.agent});

  final String? key;
  final SubagentWorkflowAgent agent;
}

class _CachedJournal {
  _CachedJournal({required this.key, required this.map});

  final String? key;
  final Map<String, _AgentJournal> map;
}

class _AgentJournal {
  _AgentJournal({required this.order});

  final int order;
  String? status;
  String? summary;
}
