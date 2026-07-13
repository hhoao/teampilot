import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../resume/pinned_transcript_probe.dart';
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
  );
  final path = probe.matchedPath;
  if (!probe.exists || path == null) return null;

  final stat = await ctx.fs.stat(path);
  if (!stat.isFile) return null;

  final bytes = await ctx.fs.readBytes(path);
  if (bytes == null) return null;

  return AiTranscriptBundle(
    adapterId: 'claude',
    fragments: [
      AiTranscriptFragment(
        name: ctx.fs.pathContext.basename(path),
        bytes: bytes,
      ),
    ],
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
