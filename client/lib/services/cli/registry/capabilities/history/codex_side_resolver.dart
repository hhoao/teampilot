import 'package:ai_message_core/ai_message_core.dart';

import '../../../../../utils/logging/logger.dart';
import '../../../../session/session_history_context.dart';
import 'codex_ai_transcript.dart';
import 'subagent_side_resolver.dart';

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

    final sidePath = await _locateRolloutForAgentId(ctx, agentId);
    if (sidePath == null) return null;

    return _buildResult(ctx, sidePath);
  }
}

// Keep in sync with `_rolloutId` in `codex_ai_transcript.dart`.
final _codexRolloutId = RegExp(
  r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
);

Future<String?> _locateRolloutForAgentId(
  SessionHistoryContext ctx,
  String agentId,
) async {
  final home = ctx.env['CODEX_HOME']?.trim() ?? '';
  if (home.isEmpty) return null;

  final path = ctx.fs.pathContext;
  final sessionsDir = path.join(home, 'sessions');
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
