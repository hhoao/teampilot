import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

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
final class ClaudeWorkflowResolver {
  const ClaudeWorkflowResolver();

  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required String? parentTranscriptPath,
  }) async {
    final parentPath = _trimmed(parentTranscriptPath);
    if (parentPath == null) return null;
    if (part.toolCallId.trim().isEmpty) return null;

    final taskId = await _taskIdForToolUse(ctx, parentPath, part.toolCallId);
    if (taskId == null) return null;

    final runRecord = await _runRecordForTaskId(ctx, parentPath, taskId);
    if (runRecord == null) return null;

    final runId = _trimmed(runRecord['runId']);
    if (runId == null) return null;

    final agents = await _loadAgents(ctx, parentPath, runId, part.toolCallId);

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

  Future<String?> _taskIdForToolUse(
    SessionHistoryContext ctx,
    String parentPath,
    String toolCallId,
  ) async {
    final content = await ctx.fs.readString(parentPath);
    if (content == null) return null;
    final notifications = _taskNotifications(content);
    return notifications[toolCallId];
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

  Future<Map<String, Object?>?> _runRecordForTaskId(
    SessionHistoryContext ctx,
    String parentPath,
    String taskId,
  ) async {
    final workflowsDir = claudeWorkflowsDirFor(parentPath);
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDir(workflowsDir);
    } catch (_) {
      return null;
    }
    for (final entry in entries) {
      if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
      final content = await ctx.fs.readString(
        ctx.fs.pathContext.join(workflowsDir, entry.name),
      );
      if (content == null) continue;
      final decoded = _tryDecodeObject(content);
      if (decoded == null) continue;
      if (_trimmed(decoded['taskId']) == taskId) return decoded;
    }
    return null;
  }

  Future<List<SubagentWorkflowAgent>> _loadAgents(
    SessionHistoryContext ctx,
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

    final journal = await _readJournal(ctx, runDir);
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
      final content = await ctx.fs.readString(filePath);
      if (content == null) continue;

      final messages = parseClaudeCompatibleJsonl(
        content,
        fallbackId: () => 'workflow-agent-$agentId-$parentToolCallId',
      );
      final j = journal[agentId];
      agents.add(
        SubagentWorkflowAgent(
          agentId: agentId,
          role: _roleFromFirstUser(messages),
          status: j?.status,
          messages: messages,
          handle: SubagentFileHandle(filePath),
        ),
      );
    }
    agents.sort(
      (a, b) =>
          (journal[a.agentId]?.order ?? 0).compareTo(
            journal[b.agentId]?.order ?? 0,
          ),
    );
    return agents;
  }

  /// Journal lines: `{"type":"started"|"result","agentId":…,"result":{…}}`.
  /// Keeps the last result per agent plus its first-seen order.
  Future<Map<String, _AgentJournal>> _readJournal(
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

class _AgentJournal {
  _AgentJournal({required this.order});

  final int order;
  String? status;
  String? summary;
}
