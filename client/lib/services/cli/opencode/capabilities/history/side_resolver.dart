import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import 'package:logger/logger.dart';
import '../../../../../utils/logging/logger.dart';
import '../../../../session/session_history_context.dart';
import 'ai_transcript.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';

final _opencodeTaskIdPattern = RegExp(r'<task id="(ses_[^"]+)">');

String? opencodeChildSessionId(AiToolCallPart part) {
  final result = part.result;
  if (result is Map) {
    final map = Map<String, dynamic>.from(result);
    final direct = _trimmedSessionId(map['sessionId']);
    if (direct != null) return direct;

    final metadata = map['metadata'];
    if (metadata is Map) {
      final fromMeta = _trimmedSessionId(
        Map<String, dynamic>.from(metadata)['sessionId'],
      );
      if (fromMeta != null) return fromMeta;
    }
  }

  final text = switch (result) {
    String s => s,
    null => null,
    _ => result.toString(),
  };
  if (text == null || text.isEmpty) return null;

  final match = _opencodeTaskIdPattern.firstMatch(text);
  return match?.group(1);
}

String? _trimmedSessionId(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

final class OpencodeSideResolver implements SubagentSideResolver {
  const OpencodeSideResolver();

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    final childSessionId = opencodeChildSessionId(part);
    if (childSessionId == null || childSessionId.isEmpty) return null;

    final bundle = await locateOpencodeTranscriptForSession(
      ctx,
      childSessionId,
    );
    if (bundle == null) return null;

    await _logParentIdMismatchIfNeeded(
      ctx: ctx,
      bundle: bundle,
      childSessionId: childSessionId,
      parentSessionId: _parentSessionId(ctx, parentHandle),
    );

    try {
      final messages = await const OpencodeAiTranscriptAdapter().parse(bundle);
      return SubagentSideResolveResult(
        messages: messages,
        handle: SubagentSessionHandle(childSessionId),
      );
    } catch (e, st) {
      appLogger.w(
        '[subagent-inflate] OpenCode child session failed '
        'sessionId=$childSessionId: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}

String? _parentSessionId(
  SessionHistoryContext ctx,
  SubagentSideHandle? parentHandle,
) {
  if (parentHandle is SubagentSessionHandle) {
    final id = parentHandle.sessionId.trim();
    if (id.isNotEmpty) return id;
  }
  final persisted = ctx.persistedNativeId?.trim();
  if (persisted != null && persisted.isNotEmpty) return persisted;
  return null;
}

Future<void> _logParentIdMismatchIfNeeded({
  required SessionHistoryContext ctx,
  required AiTranscriptBundle bundle,
  required String childSessionId,
  required String? parentSessionId,
}) async {
  final expectedParent = parentSessionId?.trim();
  if (expectedParent == null || expectedParent.isEmpty) return;

  final sessionMeta = await _sessionMetaFromBundle(ctx, bundle, childSessionId);
  if (sessionMeta == null) return;

  final actualParent =
      '${sessionMeta['parent_id'] ?? sessionMeta['parentID'] ?? ''}'.trim();
  if (actualParent.isEmpty || actualParent == expectedParent) return;

  appLogger.w(
    '[subagent-inflate] OpenCode child session parent_id mismatch '
    'child=$childSessionId expectedParent=$expectedParent '
    'actualParent=$actualParent',
  );
}

Future<Map<String, dynamic>?> _sessionMetaFromBundle(
  SessionHistoryContext ctx,
  AiTranscriptBundle bundle,
  String sessionId,
) async {
  for (final fragment in bundle.fragments) {
    if (!fragment.name.startsWith('session/')) continue;
    final obj = _tryDecodeObject(
      utf8.decode(fragment.bytes, allowMalformed: true),
    );
    if (obj != null) return obj;
  }

  final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
  if (db.isEmpty || db == ':memory:') return null;
  final dataDir = ctx.fs.pathContext.dirname(db);
  final sessionPath = await _findSessionFile(ctx, dataDir, sessionId);
  if (sessionPath == null) return null;

  final bytes = await ctx.fs.readBytes(sessionPath);
  if (bytes == null) return null;
  return _tryDecodeObject(utf8.decode(bytes, allowMalformed: true));
}

Future<String?> _findSessionFile(
  SessionHistoryContext ctx,
  String dataDir,
  String sessionId,
) async {
  final path = ctx.fs.pathContext;
  final sessionDir = path.join(dataDir, 'storage', 'session');
  try {
    final entries = await ctx.fs.listDirRecursive(sessionDir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (path.basename(e.name) != '$sessionId.json') continue;
      return path.join(sessionDir, e.name);
    }
  } on Object {
    return null;
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
