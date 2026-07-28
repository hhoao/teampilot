import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import '../../../../session/subagent_side_transcript_path.dart';
import 'cursor_ai_transcript.dart';
import 'subagent_side_resolver.dart';

final class CursorSideResolver implements SubagentSideResolver {
  const CursorSideResolver();

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

    final transcriptsRoot = cursorAgentTranscriptsRootFor(
      parentTranscriptPath,
      pathContext: ctx.fs.pathContext,
    );
    if (transcriptsRoot == null) return null;

    final resumeUuid = _resumeUuidFromPart(part);
    if (resumeUuid != null) {
      return _resolveByUuid(
        ctx: ctx,
        transcriptsRoot: transcriptsRoot,
        uuid: resumeUuid,
      );
    }

    return _resolveByPromptHeuristic(
      ctx: ctx,
      part: part,
      transcriptsRoot: transcriptsRoot,
      parentTranscriptPath: parentTranscriptPath,
      toolCallAt: toolCallAt,
    );
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
}

/// Cursor layout: parent `…/agent-transcripts/{stem}/{stem}.jsonl` or flat
/// `…/agent-transcripts/{id}.jsonl` → root `…/agent-transcripts`.
String? cursorAgentTranscriptsRootFor(
  String parentTranscriptPath, {
  p.Context? pathContext,
}) {
  final path = pathContext ?? pathContextForTranscript(parentTranscriptPath);
  final normalized = path.normalize(parentTranscriptPath);
  final parentDir = path.dirname(normalized);
  final stem = path.basenameWithoutExtension(normalized);
  if (stem.isEmpty) return null;

  if (path.basename(parentDir) == stem) {
    return path.dirname(parentDir);
  }
  if (path.basename(parentDir) == 'agent-transcripts') {
    return parentDir;
  }
  return null;
}

String? _resumeUuidFromPart(AiToolCallPart part) {
  final args = part.args;
  if (args != null) {
    for (final key in const ['resume', 'agentId', 'agent_id']) {
      final value = args[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
  }
  return subagentAgentIdFromPart(part);
}

Future<SubagentSideResolveResult?> _resolveByUuid({
  required SessionHistoryContext ctx,
  required String transcriptsRoot,
  required String uuid,
}) async {
  final path = ctx.fs.pathContext;
  final nested = path.join(transcriptsRoot, uuid, '$uuid.jsonl');
  if ((await ctx.fs.stat(nested)).isFile) {
    return _buildResult(ctx, nested);
  }
  final flat = path.join(transcriptsRoot, '$uuid.jsonl');
  if ((await ctx.fs.stat(flat)).isFile) {
    return _buildResult(ctx, flat);
  }
  return null;
}

Future<SubagentSideResolveResult?> _resolveByPromptHeuristic({
  required SessionHistoryContext ctx,
  required AiToolCallPart part,
  required String transcriptsRoot,
  required String parentTranscriptPath,
  DateTime? toolCallAt,
}) async {
  final prompt = _taskPromptFromPart(part);
  if (prompt == null) return null;

  final normalizedPrompt = normalizeCursorTaskPrompt(prompt);
  if (normalizedPrompt == null) return null;

  final parentStem =
      ctx.fs.pathContext.basenameWithoutExtension(parentTranscriptPath);
  final parentMtime = (await ctx.fs.stat(parentTranscriptPath)).mtime;
  final referenceAt = toolCallAt ?? parentMtime;
  if (referenceAt == null) return null;

  final candidates = await _collectPromptMatches(
    ctx: ctx,
    transcriptsRoot: transcriptsRoot,
    normalizedPrompt: normalizedPrompt,
    excludeStem: parentStem,
    referenceAt: referenceAt,
  );
  if (candidates.isEmpty) return null;

  final bestDistance = candidates
      .map((c) => c.distance.inMicroseconds.abs())
      .reduce((a, b) => a < b ? a : b);
  final winners = candidates
      .where((c) => c.distance.inMicroseconds.abs() == bestDistance)
      .toList();
  if (winners.length != 1) return null;

  return _buildResult(ctx, winners.single.path);
}

String? _taskPromptFromPart(AiToolCallPart part) {
  final args = part.args;
  if (args == null) return null;
  for (final key in const ['prompt', 'description']) {
    final value = args[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }
  return null;
}

Future<List<_PromptMatchCandidate>> _collectPromptMatches({
  required SessionHistoryContext ctx,
  required String transcriptsRoot,
  required String normalizedPrompt,
  required String excludeStem,
  required DateTime referenceAt,
}) async {
  final path = ctx.fs.pathContext;
  final matches = <_PromptMatchCandidate>[];

  List<FsDirEntry> entries;
  try {
    entries = await ctx.fs.listDir(transcriptsRoot);
  } catch (_) {
    return matches;
  }

  for (final entry in entries) {
    if (entry.name == excludeStem) continue;
    if (entry.name == 'subagents') continue;

    final candidatePaths = <String>[];
    if (entry.isDirectory) {
      candidatePaths.add(
        path.join(transcriptsRoot, entry.name, '${entry.name}.jsonl'),
      );
    } else if (entry.name.endsWith('.jsonl')) {
      candidatePaths.add(path.join(transcriptsRoot, entry.name));
    }

    for (final candidatePath in candidatePaths) {
      if (path.basenameWithoutExtension(candidatePath) == excludeStem) {
        continue;
      }
      if ((await ctx.fs.stat(candidatePath)).kind != FsEntityKind.file) {
        continue;
      }

      final content = await ctx.fs.readString(candidatePath);
      if (content == null) continue;

      final firstUser = _firstUserTextFromCursorJsonl(content);
      if (firstUser == null) continue;
      if (normalizeCursorTaskPrompt(firstUser) != normalizedPrompt) continue;

      final mtime = (await ctx.fs.stat(candidatePath)).mtime;
      if (mtime == null) continue;

      matches.add(
        _PromptMatchCandidate(
          path: candidatePath,
          distance: mtime.difference(referenceAt),
        ),
      );
    }
  }

  return matches;
}

class _PromptMatchCandidate {
  const _PromptMatchCandidate({required this.path, required this.distance});

  final String path;
  final Duration distance;
}

String? _firstUserTextFromCursorJsonl(String content) {
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final event = _tryDecodeObject(trimmed);
    if (event == null) continue;
    if (event['role'] != 'user') continue;

    final message = event['message'];
    if (message is! Map) continue;
    final messageContent = message['content'];
    if (messageContent is String) {
      return messageContent;
    }
    if (messageContent is List) {
      for (final block in messageContent) {
        if (block is! Map) continue;
        if (block['type'] == 'text') {
          return '${block['text'] ?? ''}';
        }
      }
    }
  }
  return null;
}

Map<String, dynamic>? _tryDecodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// Unwrap Cursor IDE wrappers (`<user_query>`, `<timestamp>`) for Task matching.
String? normalizeCursorTaskPrompt(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;

  text = text.replaceAll(
    RegExp(r'<timestamp>[\s\S]*?</timestamp>\s*', multiLine: true),
    '',
  );

  final query = RegExp(
    r'<user_query>\s*([\s\S]*?)\s*</user_query>',
    multiLine: true,
  ).firstMatch(text);
  if (query != null) {
    text = (query.group(1) ?? '').trim();
  }

  text = text.trim();
  return text.isEmpty ? null : text;
}

Future<SubagentSideResolveResult?> _buildResult(
  SessionHistoryContext ctx,
  String sidePath,
) async {
  try {
    final bytes = await ctx.fs.readBytes(sidePath);
    if (bytes == null) return null;

    final bundle = AiTranscriptBundle(
      adapterId: 'cursor',
      fragments: [
        AiTranscriptFragment(
          name: ctx.fs.pathContext.basename(sidePath),
          bytes: bytes,
        ),
      ],
    );
    final messages = await const CursorAiTranscriptAdapter().parse(bundle);
    return SubagentSideResolveResult(
      messages: messages,
      handle: SubagentFileHandle(sidePath),
    );
  } catch (e, st) {
    appLogger.w(
      '[subagent-inflate] Cursor side transcript failed path=$sidePath: $e',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}
