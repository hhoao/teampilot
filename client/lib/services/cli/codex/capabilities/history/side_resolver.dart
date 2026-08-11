import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import 'package:logger/logger.dart';
import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import 'ai_transcript.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';

final class CodexSideResolver implements SubagentSideResolver {
  const CodexSideResolver();

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    final agentId = subagentAgentIdFromPart(part);
    if (agentId == null || agentId.isEmpty) return null;

    final home = ctx.env['CODEX_HOME']?.trim() ?? '';
    if (home.isEmpty) return null;

    final path = ctx.fs.pathContext;
    final sessionsDir = path.join(home, 'sessions');
    final parentTranscriptPath = _parentTranscriptPath(
      parentHandle,
      rootTranscriptPath,
    );

    final String? sidePath;
    if (parentTranscriptPath != null &&
        _isUnderCodexSessions(parentTranscriptPath, sessionsDir)) {
      sidePath = await _locateRolloutScoped(
        ctx: ctx,
        searchRoot: path.dirname(parentTranscriptPath),
        agentId: agentId,
      );
    } else {
      sidePath = await _locateRolloutGlobal(
        ctx: ctx,
        sessionsDir: sessionsDir,
        agentId: agentId,
      );
    }
    if (sidePath == null) return null;

    return _buildResult(ctx, sidePath);
  }

  // The agent id (and thus the rollout) is only discoverable from the tool
  // args/result; there is no cheap dir-level fingerprint, and the parent cache
  // token already misses for Codex (rollout JSONL is not under projects/),
  // so every live refresh re-inflates anyway.
  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async => null;

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
}

// Keep in sync with `_rolloutId` in `codex_ai_transcript.dart`.
final _codexRolloutId = RegExp(
  r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
);

bool _isUnderCodexSessions(String filePath, String sessionsDir) {
  final normalizedFile = p.normalize(filePath);
  final normalizedSessions = p.normalize(sessionsDir);
  return p.equals(normalizedFile, normalizedSessions) ||
      p.isWithin(normalizedSessions, normalizedFile);
}

Future<String?> _locateRolloutScoped({
  required SessionHistoryContext ctx,
  required String searchRoot,
  required String agentId,
}) async {
  final wanted = agentId.trim().toLowerCase();
  final path = ctx.fs.pathContext;

  final inRoot = await _bestRolloutInDirectory(ctx, searchRoot, wanted);
  if (inRoot != null) return inRoot;

  List<FsDirEntry> entries;
  try {
    entries = await ctx.fs.listDir(searchRoot);
  } on Object {
    return null;
  }

  var bestPath = '';
  for (final entry in entries) {
    if (!entry.isDirectory) continue;
    if (entry.name == 'subagents') continue;
    final candidate = await _bestRolloutInDirectory(
      ctx,
      path.join(searchRoot, entry.name),
      wanted,
    );
    if (candidate != null && candidate.compareTo(bestPath) > 0) {
      bestPath = candidate;
    }
  }
  return bestPath.isEmpty ? null : bestPath;
}

Future<String?> _bestRolloutInDirectory(
  SessionHistoryContext ctx,
  String directory,
  String wantedAgentId,
) async {
  final path = ctx.fs.pathContext;
  List<FsDirEntry> entries;
  try {
    entries = await ctx.fs.listDir(directory);
  } on Object {
    return null;
  }

  var bestPath = '';
  for (final entry in entries) {
    if (entry.isDirectory) continue;
    if (_isUnderSubagents(entry.name)) continue;
    final name = path.basename(entry.name);
    final match = _codexRolloutId.firstMatch(name);
    if (match == null) continue;
    final id = match.group(1)?.toLowerCase() ?? '';
    if (id != wantedAgentId) continue;
    final fullPath = path.join(directory, entry.name);
    if (fullPath.compareTo(bestPath) > 0) bestPath = fullPath;
  }
  return bestPath.isEmpty ? null : bestPath;
}

Future<String?> _locateRolloutGlobal({
  required SessionHistoryContext ctx,
  required String sessionsDir,
  required String agentId,
}) async {
  final path = ctx.fs.pathContext;
  final wanted = agentId.trim().toLowerCase();

  var bestRel = '';
  try {
    final entries = await ctx.fs.listDirRecursive(sessionsDir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (_isUnderSubagents(e.name)) continue;
      final name = path.basename(e.name);
      final match = _codexRolloutId.firstMatch(name);
      if (match == null) continue;
      final id = match.group(1)?.toLowerCase() ?? '';
      if (id != wanted) continue;
      if (e.name.compareTo(bestRel) > 0) bestRel = e.name;
    }
  } on Object {
    return null;
  }
  if (bestRel.isEmpty) return null;
  return path.join(sessionsDir, bestRel);
}

bool _isUnderSubagents(String relativePath) {
  return relativePath.split(RegExp(r'[/\\]')).contains('subagents');
}

Future<SubagentSideResolveResult?> _buildResult(
  SessionHistoryContext ctx,
  String sidePath,
) async {
  try {
    final bytes = await ctx.fs.readBytes(sidePath);
    if (bytes == null) return null;

    final bundle = AiTranscriptBundle(
      adapterId: 'codex',
      fragments: [
        AiTranscriptFragment(
          name: ctx.fs.pathContext.basename(sidePath),
          bytes: bytes,
        ),
      ],
    );
    final messages = await const CodexAiTranscriptAdapter().parse(bundle);
    return SubagentSideResolveResult(
      messages: messages,
      handle: SubagentFileHandle(sidePath),
    );
  } catch (e, st) {
    appLogger.w(
      '[subagent-inflate] Codex side rollout failed path=$sidePath: $e',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}
