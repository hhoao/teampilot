import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';

/// Gemini CLI native usage.
///
/// Completed turns are persisted under `GEMINI_CONFIG_DIR/tmp/{project}/
/// chats/session-*.json(l)`. Newer CLIs write JSONL; older ones write one JSON
/// document. A `type: "gemini"` message carries the model and the token split
/// (`input`, `cached`, `output`, `thoughts`). `input` includes cached tokens,
/// so the event keeps total semantics and lets the aggregator subtract cache.
final class GeminiSessionUsageCapability implements SessionUsageCapability {
  const GeminiSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final path = ctx.fs.pathContext;
    final configDir = ctx.env['GEMINI_CONFIG_DIR']?.trim() ?? '';
    final roots = <String>{
      if (configDir.isNotEmpty) configDir,
      if (configDir.isEmpty) ...ctx.transcriptRoots,
    };

    final out = <SessionUsageSource>[];
    final seen = <String>{};
    for (final root in roots) {
      final tmp = path.join(root, 'tmp');
      if (!(await ctx.fs.stat(tmp)).isDirectory) continue;
      for (final entry in await ctx.fs.listDirRecursive(tmp)) {
        if (entry.isDirectory) continue;
        final full = path.join(tmp, entry.name);
        final basename = path.basename(entry.name);
        if (!basename.startsWith('session-')) continue;
        if (!basename.endsWith('.json') && !basename.endsWith('.jsonl')) {
          continue;
        }
        if (!seen.add(full)) continue;
        out.add(
          SessionUsageSource(
            id: 'gemini-jsonl:$full',
            path: full,
            kind: UsageSourceKind.jsonl,
            sessionId: ctx.sessionId,
            memberId: ctx.memberId,
            teamId: ctx.teamId,
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    if (source.path.endsWith('.jsonl')) {
      return _scanJsonl(ctx: ctx, source: source, cursor: cursor);
    }
    return _scanJson(ctx: ctx, source: source, cursor: cursor);
  }

  Future<UsageScanResult> _scanJsonl({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    final window = await readJsonlUsageWindow(
      fs: ctx.fs,
      path: source.path,
      cursor: cursor,
    );
    if (window.pinnedToEof) {
      return _scanJsonlFull(ctx: ctx, source: source);
    }
    var sessionId = cursor?.storeToken?.trim() ?? '';
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    final startLine =
        (window.nextCursor.lineOffset ?? window.lines.length) -
        window.lines.length;
    for (var i = 0; i < window.lines.length; i++) {
      if (i % 500 == 0) await Future<void>.delayed(Duration.zero);
      final line = window.lines[i].trim();
      if (line.isEmpty) continue;
      Map<String, Object?>? obj;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) obj = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (obj == null) {
        skipped++;
        continue;
      }
      final headerId = obj['sessionId']?.toString().trim() ?? '';
      if (headerId.isNotEmpty) sessionId = headerId;
      final event = _eventFromMessage(
        ctx: ctx,
        msg: obj,
        fallbackSessionId: sessionId.isEmpty ? ctx.sessionId : sessionId,
        fallbackOrdinal: startLine + i,
      );
      if (event != null) events.add(event);
    }
    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(
        byteOffset: window.nextCursor.byteOffset,
        mtimeMs: window.nextCursor.mtimeMs,
        size: window.nextCursor.size,
        tailFingerprint: window.nextCursor.tailFingerprint,
        lineOffset: window.nextCursor.lineOffset,
        storeToken: sessionId.isEmpty ? null : sessionId,
      ),
      partialTail: window.partialTail,
      skippedLines: skipped,
    );
  }

  Future<UsageScanResult> _scanJsonlFull({
    required UsageScanContext ctx,
    required SessionUsageSource source,
  }) async {
    final stat = await ctx.fs.stat(source.path);
    final size = stat.size ?? 0;
    final mtimeMs = stat.mtime?.millisecondsSinceEpoch ?? 0;
    final raw = await ctx.fs.readString(source.path);
    if (raw == null || raw.trim().isEmpty) {
      return UsageScanResult(
        events: const [],
        nextCursor: UsageCursor(mtimeMs: mtimeMs, size: size),
      );
    }
    final lines = const LineSplitter().convert(raw);
    var sessionId = '';
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    for (var i = 0; i < lines.length; i++) {
      if (i % 500 == 0) await Future<void>.delayed(Duration.zero);
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      Map<String, Object?>? obj;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) obj = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (obj == null) {
        skipped++;
        continue;
      }
      final headerId = obj['sessionId']?.toString().trim() ?? '';
      if (headerId.isNotEmpty) sessionId = headerId;
      final event = _eventFromMessage(
        ctx: ctx,
        msg: obj,
        fallbackSessionId: sessionId.isEmpty ? ctx.sessionId : sessionId,
        fallbackOrdinal: i,
      );
      if (event != null) events.add(event);
    }
    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(
        byteOffset: size,
        mtimeMs: mtimeMs,
        size: size,
        lineOffset: lines.length,
        storeToken: sessionId.isEmpty ? null : sessionId,
      ),
      skippedLines: skipped,
    );
  }

  Future<UsageScanResult> _scanJson({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    final stat = await ctx.fs.stat(source.path);
    final size = stat.size ?? 0;
    final mtimeMs = stat.mtime?.millisecondsSinceEpoch ?? 0;
    if (cursor != null &&
        cursor.size == size &&
        cursor.mtimeMs == mtimeMs &&
        cursor.storeToken != null) {
      return UsageScanResult(events: const [], nextCursor: cursor);
    }
    final raw = await ctx.fs.readString(source.path);
    if (raw == null || raw.trim().isEmpty) {
      return UsageScanResult(
        events: const [],
        nextCursor: UsageCursor(mtimeMs: mtimeMs, size: size),
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return UsageScanResult(
        events: const [],
        nextCursor: UsageCursor(mtimeMs: mtimeMs, size: size),
        skippedLines: 1,
      );
    }
    if (decoded is! Map) {
      return UsageScanResult(
        events: const [],
        nextCursor: UsageCursor(mtimeMs: mtimeMs, size: size),
        skippedLines: 1,
      );
    }
    final root = Map<String, Object?>.from(decoded);
    final sessionId = root['sessionId']?.toString().trim().isNotEmpty == true
        ? root['sessionId']!.toString().trim()
        : ctx.sessionId;
    final messages = root['messages'];
    final events = <SessionUsageEvent>[];
    if (messages is List) {
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (message is! Map) continue;
        final event = _eventFromMessage(
          ctx: ctx,
          msg: Map<String, Object?>.from(message),
          fallbackSessionId: sessionId,
          fallbackOrdinal: i,
        );
        if (event != null) events.add(event);
      }
    }
    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(
        mtimeMs: mtimeMs,
        size: size,
        storeToken: sessionId,
      ),
    );
  }

  SessionUsageEvent? _eventFromMessage({
    required UsageScanContext ctx,
    required Map<String, Object?> msg,
    required String fallbackSessionId,
    required int fallbackOrdinal,
  }) {
    if (msg['type'] != 'gemini') return null;
    final tokensRaw = msg['tokens'];
    if (tokensRaw is! Map) return null;
    final tokens = Map<String, Object?>.from(tokensRaw);
    final input = _int(tokens['input']);
    final cached = _int(tokens['cached']);
    final output = _int(tokens['output']);
    final thoughts = _int(tokens['thoughts']);
    if (input == 0 && cached == 0 && output == 0 && thoughts == 0) {
      return null;
    }
    final model = msg['model']?.toString().trim() ?? '';
    if (model.isEmpty) return null;
    final id = msg['id']?.toString().trim() ?? '';
    final messageKey = id.isEmpty ? 'idx-$fallbackOrdinal' : id;
    return SessionUsageEvent(
      requestId: 'gemini:$fallbackSessionId:$messageKey',
      cli: CliTool.gemini,
      model: model,
      inputTokens: input,
      outputTokens: output + thoughts,
      cacheReadTokens: cached,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.total,
      timestampMs: _timestampMs(msg['timestamp']),
      sessionId: ctx.sessionId,
      memberId: ctx.memberId,
      teamId: ctx.teamId,
    );
  }
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

int _timestampMs(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}
