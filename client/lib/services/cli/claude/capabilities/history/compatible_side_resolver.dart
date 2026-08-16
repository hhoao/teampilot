import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';

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

    // side 文件 memo:stat 签名(size+mtime)未变时复用同一解析结果——
    // 消息列表实例相同,loader/seat 的 identical 快速路径生效,活跃子
    // agent 每 tick 重 inflate 时未变化的子会话零重解析、零内容比较。
    final stat = await ctx.fs.stat(sidePath);
    if (!stat.isFile) return null;
    final statSig =
        '${stat.size ?? 0}|${stat.mtime?.toUtc().toIso8601String() ?? ''}';
    final memo = _sideMemos[sidePath];
    if (memo != null && memo.sig == statSig) {
      return SubagentSideResolveResult(
        messages: memo.messages,
        handle: SubagentFileHandle(sidePath),
      );
    }

    try {
      final content = await ctx.fs.readString(sidePath);
      if (content == null) return null;
      final sideMessages = parseClaudeCompatibleJsonl(
        content,
        fallbackId: () => 'subagent-$agentId-${part.toolCallId}',
      );
      _sideMemos[sidePath] = _SideFileMemo(
        sig: statSig,
        messages: sideMessages,
      );
      _evictSideMemos();
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

  /// 每目录 meta map memo:subagentsDir → (目录签名, toolUseId→agentId)。
  /// 一次目录指纹走查服务同一 tick 的所有 part resolve(meta 文件很小,
  /// 签名走查 + 一次扫描就够,未变化时 O(1) 复用)。
  static final Map<String, _MetaMemo> _metaMemos = {};
  static const int _metaMemoCap = 32;

  static void _evictMetaMemos() {
    if (_metaMemos.length <= _metaMemoCap) return;
    _metaMemos.removeWhere(
      (_, __) => _metaMemos.length > _metaMemoCap,
    );
  }

  /// side 文件解析 memo(见 [resolve] 的注释)。
  static final Map<String, _SideFileMemo> _sideMemos = {};
  static const int _sideMemoCap = 128;

  static void _evictSideMemos() {
    if (_sideMemos.length <= _sideMemoCap) return;
    _sideMemos.removeWhere(
      (_, __) => _sideMemos.length > _sideMemoCap,
    );
  }

  @visibleForTesting
  static void clearMemo() {
    _metaMemos.clear();
    _sideMemos.clear();
  }

  Future<Map<String, String>> _loadMetaMap(
    SessionHistoryContext ctx,
    String parentTranscriptPath,
  ) async {
    final subagentsDir = claudeSubagentsDirFor(
      parentTranscriptPath,
      pathContext: ctx.fs.pathContext,
    );
    final sig = await _metaDirSig(ctx, subagentsDir);
    if (sig == null) return const {};
    final memo = _metaMemos[subagentsDir];
    if (memo != null && memo.sig == sig) return memo.map;

    final map = await _scanMetaMap(ctx, subagentsDir);
    _metaMemos[subagentsDir] = _MetaMemo(sig: sig, map: map);
    _evictMetaMemos();
    return map;
  }

  /// meta 文件集合的目录签名;目录缺失返回 null(与旧 listDir 抛错 →
  /// 空 map 语义一致,但不 memo 化——缺失时每次 resolve 只做一次 stat)。
  static Future<String?> _metaDirSig(
    SessionHistoryContext ctx,
    String dir,
  ) async {
    final stat = await ctx.fs.stat(dir);
    if (!stat.isDirectory) return null;
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDir(dir);
    } on Object {
      return null;
    }
    final path = ctx.fs.pathContext;
    final parts = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      if (!entry.name.startsWith('agent-') ||
          !entry.name.endsWith('.meta.json')) {
        continue;
      }
      final full = path.join(dir, entry.name);
      final st = await ctx.fs.stat(full);
      if (!st.exists) continue;
      parts.add(
        '${entry.name}|${st.size ?? 0}|${st.mtime?.toUtc().toIso8601String() ?? ''}',
      );
    }
    return parts.join('\n');
  }

  Future<Map<String, String>> _scanMetaMap(
    SessionHistoryContext ctx,
    String subagentsDir,
  ) async {
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

/// side 文件解析 memo:stat 签名 → 解析结果(见 resolve 注释)。
class _SideFileMemo {
  const _SideFileMemo({required this.sig, required this.messages});

  final String sig;
  final List<AiMessage> messages;
}

/// meta map memo:目录签名 → toolUseId→agentId。
class _MetaMemo {
  const _MetaMemo({required this.sig, required this.map});

  final String sig;
  final Map<String, String> map;
}
