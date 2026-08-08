import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../resume/pinned_transcript_probe.dart';
import '../../../../session/ai_history_cache_token.dart';
import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';
import 'claude_compatible_jsonl.dart';

/// Locate Claude Code JSONL under `{root}/projects/{bucket}/{taskId}.jsonl`.
Future<AiTranscriptBundle?> locateClaudeTranscript(
  SessionHistoryContext ctx,
) async {
  final probe = await probePinnedTranscript(
    fs: ctx.fs,
    toolRoots: ctx.transcriptRoots,
    sessionId: ctx.taskId,
    bucket: ctx.bucket,
    layoutSegments: const ['projects'],
    // History parse needs the transcript file itself; a `{sessionId}/`
    // sidecar directory (workflow scripts) must not shadow it.
    matchDirectories: false,
  );
  final path = probe.matchedPath;
  if (!probe.exists || path == null) return null;

  final stat = await ctx.fs.stat(path);
  if (!stat.isFile) return null;

  final bytes = await ctx.fs.readBytes(path);
  if (bytes == null) return null;

  final cacheToken = await aiHistoryPathCacheToken(
    fs: ctx.fs,
    path: path,
    byteLength: bytes.length,
  );
  return AiTranscriptBundle(
    adapterId: 'claude',
    fragments: [
      AiTranscriptFragment(
        name: ctx.fs.pathContext.basename(path),
        bytes: bytes,
      ),
    ],
    hints: {
      'cacheToken': cacheToken,
      ...AiHistoryWatchMeta(
        changeWatchRoot: ctx.fs.pathContext.dirname(path),
        cacheTokenPaths: [path],
      ).toHints(),
    },
  );
}

/// Claude Code JSONL → [AiMessage] with text / reasoning / tool-call parts.
final class ClaudeAiTranscriptAdapter implements AiTranscriptAdapter {
  const ClaudeAiTranscriptAdapter();

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final messages = <AiMessage>[];
    var fallbackSeq = 0;

    for (final fragment in bundle.fragments) {
      final content = utf8.decode(fragment.bytes, allowMalformed: true);
      messages.addAll(
        parseClaudeCompatibleJsonl(
          content,
          fallbackId: () => 'claude-${fallbackSeq++}',
        ),
      );
    }

    return messages;
  }
}
