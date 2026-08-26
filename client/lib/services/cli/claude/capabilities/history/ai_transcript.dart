import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/resume/pinned_transcript_probe.dart';
import '../../../../session/ai_history_cache_token.dart';
import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';
import 'compatible_jsonl.dart';

/// Probes the persisted id first (duplicated sessions), then [ctx.taskId].
/// `matchDirectories: false` in both probes: history parse needs the `.jsonl`
/// file itself; a `{sessionId}/` sidecar directory must not shadow it.
Future<PinnedTranscriptProbeResult> _locateProbe(
  SessionHistoryContext ctx,
) async {
  final persisted = ctx.persistedNativeId?.trim() ?? '';
  if (persisted.isNotEmpty) {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: persisted,
      bucket: ctx.bucket,
      layoutSegments: const ['projects'],
      matchDirectories: false,
    );
    if (probe.exists) return probe;
  }
  return probePinnedTranscript(
    fs: ctx.fs,
    toolRoots: ctx.transcriptRoots,
    sessionId: ctx.taskId,
    bucket: ctx.bucket,
    layoutSegments: const ['projects'],
    matchDirectories: false,
  );
}

/// Locate Claude Code JSONL under `{root}/projects/{bucket}/{id}.jsonl`,
/// probing the persisted id first, then [SessionHistoryContext.taskId].
Future<AiTranscriptBundle?> locateClaudeTranscript(
  SessionHistoryContext ctx,
) async {
  final probe = await _locateProbe(ctx);
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
