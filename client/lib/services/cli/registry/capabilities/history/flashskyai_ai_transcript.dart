import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../resume/pinned_transcript_probe.dart';
import '../../../../session/ai_history_cache_token.dart';
import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';
import 'claude_compatible_jsonl.dart';

/// Locate flashskyai JSONL under `{root}/projects|workspaces/{bucket}/{id}.jsonl`.
///
/// On-disk installs observed under `~/.flashskyai/projects/…` (not
/// `workspaces/`). Keep `workspaces` as a secondary probe for older layouts.
Future<AiTranscriptBundle?> locateFlashskyaiTranscript(
  SessionHistoryContext ctx,
) async {
  final probe = await probePinnedTranscript(
    fs: ctx.fs,
    toolRoots: ctx.transcriptRoots,
    sessionId: ctx.taskId,
    bucket: ctx.bucket,
    layoutSegments: const ['projects', 'workspaces'],
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
    adapterId: 'flashskyai',
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

/// flashskyai JSONL → [AiMessage] (same shapes as Claude Code).
final class FlashskyaiAiTranscriptAdapter implements AiTranscriptAdapter {
  const FlashskyaiAiTranscriptAdapter();

  @override
  String get id => 'flashskyai';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final messages = <AiMessage>[];
    var fallbackSeq = 0;

    for (final fragment in bundle.fragments) {
      final content = utf8.decode(fragment.bytes, allowMalformed: true);
      messages.addAll(
        parseClaudeCompatibleJsonl(
          content,
          fallbackId: () => 'flashskyai-${fallbackSeq++}',
        ),
      );
    }

    return messages;
  }
}
