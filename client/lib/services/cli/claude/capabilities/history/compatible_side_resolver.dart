import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import 'package:logger/logger.dart';
import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import '../../../../session/subagent_side_transcript_path.dart';
import 'compatible_jsonl.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';

final class ClaudeCompatibleSideResolver implements SubagentSideResolver {
  const ClaudeCompatibleSideResolver();

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    final parentTranscriptPath = _parentTranscriptPath(
      parentHandle,
      rootTranscriptPath,
    );
    if (parentTranscriptPath == null) return null;

    final metaByToolUseId = await _loadMetaMap(ctx, parentTranscriptPath);
    final agentId =
        metaByToolUseId[part.toolCallId] ?? subagentAgentIdFromPart(part);
    if (agentId == null || agentId.isEmpty) return null;

    final subagentsDir = claudeSubagentsDirFor(
      parentTranscriptPath,
      pathContext: ctx.fs.pathContext,
    );
    final sidePath = claudeSubagentTranscriptPath(
      subagentsDir: subagentsDir,
      agentId: agentId,
      pathContext: ctx.fs.pathContext,
    );
    try {
      final content = await ctx.fs.readString(sidePath);
      if (content == null) return null;
      final sideMessages = parseClaudeCompatibleJsonl(
        content,
        fallbackId: () => 'subagent-$agentId-${part.toolCallId}',
      );
      return SubagentSideResolveResult(
        messages: sideMessages,
        handle: SubagentFileHandle(sidePath),
      );
    } catch (e, st) {
      appLogger.w(
        '[subagent-inflate] side transcript failed '
        'toolCallId=${part.toolCallId} path=$sidePath: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  static String? _parentTranscriptPath(
    SubagentSideHandle? parentHandle,
    String? rootTranscriptPath,
  ) {
    if (parentHandle is SubagentFileHandle) {
      final path = parentHandle.path.trim();
      if (path.isNotEmpty) return path;
    }
    final root = rootTranscriptPath?.trim();
    if (root != null && root.isNotEmpty) return root;
    return null;
  }

  Future<Map<String, String>> _loadMetaMap(
    SessionHistoryContext ctx,
    String parentTranscriptPath,
  ) async {
    final subagentsDir = claudeSubagentsDirFor(
      parentTranscriptPath,
      pathContext: ctx.fs.pathContext,
    );
    final map = <String, String>{};
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDir(subagentsDir);
    } catch (_) {
      return map;
    }

    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (!name.startsWith('agent-') || !name.endsWith('.meta.json')) {
        continue;
      }
      final agentId = name.substring(
        'agent-'.length,
        name.length - '.meta.json'.length,
      );
      if (agentId.isEmpty) continue;

      final metaPath = ctx.fs.pathContext.join(subagentsDir, name);
      String? raw;
      try {
        raw = await ctx.fs.readString(metaPath);
      } catch (e, st) {
        appLogger.w(
          '[subagent-inflate] meta read failed path=$metaPath: $e',
          error: e,
          stackTrace: st,
        );
        continue;
      }
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final toolUseId = decoded['toolUseId'];
        if (toolUseId is! String) continue;
        final trimmed = toolUseId.trim();
        if (trimmed.isEmpty) continue;
        map[trimmed] = agentId;
      } catch (e, st) {
        appLogger.w(
          '[subagent-inflate] meta parse failed path=$metaPath: $e',
          error: e,
          stackTrace: st,
        );
        continue;
      }
    }
    return map;
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async {
    final parent = _parentTranscriptPath(null, rootTranscriptPath);
    if (parent == null) return null;
    final subagentsDir = claudeSubagentsDirFor(
      parent,
      pathContext: ctx.fs.pathContext,
    );
    final stat = await ctx.fs.stat(subagentsDir);
    if (!stat.isDirectory) return null;

    final parts = <String>[];
    await _fingerprintDir(ctx, subagentsDir, parts);
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// Recursive walk of the `subagents/` tree — regular `agent-*.jsonl` /
  /// `.meta.json` files plus `workflows/wf_*/` run dirs that append while a
  /// Workflow orchestration runs.
  static Future<void> _fingerprintDir(
    SessionHistoryContext ctx,
    String dir,
    List<String> out,
  ) async {
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDir(dir);
    } on Object {
      return;
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    final path = ctx.fs.pathContext;
    for (final entry in entries) {
      final full = path.join(dir, entry.name);
      if (entry.isDirectory) {
        await _fingerprintDir(ctx, full, out);
        continue;
      }
      if (!entry.name.endsWith('.jsonl') &&
          !entry.name.endsWith('.meta.json')) {
        continue;
      }
      final st = await ctx.fs.stat(full);
      if (!st.exists) continue;
      out.add(
        '${entry.name}|${st.size ?? 0}|${st.mtime?.toUtc().toIso8601String() ?? ''}',
      );
    }
  }
}
