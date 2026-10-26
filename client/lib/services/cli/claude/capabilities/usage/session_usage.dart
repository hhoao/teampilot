import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';

final class ClaudeSessionUsageCapability implements SessionUsageCapability {
  const ClaudeSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final ids = {
      for (final id in [ctx.nativeSessionId, ctx.taskId])
        if (id.trim().isNotEmpty) id.trim(),
    };
    if (ids.isEmpty) return const [];

    final path = ctx.fs.pathContext;
    final seen = <String>{};
    final out = <SessionUsageSource>[];
    for (final root in ctx.transcriptRoots) {
      final projects = path.join(root, 'projects');
      if (!(await ctx.fs.stat(projects)).isDirectory) continue;
      for (final entry in await ctx.fs.listDirRecursive(projects)) {
        if (entry.isDirectory) continue;
        final segments = path.split(entry.name);
        final basename = path.basename(entry.name);
        if (!basename.endsWith('.jsonl')) continue;
        final owned = ids.any(
          (id) =>
              basename == '$id.jsonl' ||
              (segments.length > 1 && segments.skip(1).contains(id)),
        );
        if (!owned) continue;
        final full = path.join(projects, entry.name);
        if (!seen.add(full)) continue;
        out.add(
          SessionUsageSource(
            id: 'claude-jsonl:$full',
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
    final window = await readJsonlUsageWindow(
      fs: ctx.fs,
      path: source.path,
      cursor: cursor,
    );
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    for (var i = 0; i < window.lines.length; i++) {
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
      if (obj['type'] != 'assistant') continue;
      final messageRaw = obj['message'];
      if (messageRaw is! Map) continue;
      final message = Map<String, Object?>.from(messageRaw);
      final usageRaw = message['usage'];
      if (usageRaw is! Map) continue;
      final usage = Map<String, Object?>.from(usageRaw);
      final input = _int(usage['input_tokens']);
      final output = _int(usage['output_tokens']);
      final cacheRead = _int(usage['cache_read_input_tokens']);
      final cacheCreate = _int(usage['cache_creation_input_tokens']);
      final cacheMap = usage['cache_creation'];
      final cache1h = cacheMap is Map
          ? _int(cacheMap['ephemeral_1h_input_tokens'])
          : 0;
      if (input == 0 && output == 0 && cacheRead == 0 && cacheCreate == 0) {
        continue;
      }
      final messageId = '${message['id'] ?? ''}'.trim();
      if (messageId.isEmpty) continue;
      final stopReason = message['stop_reason'];
      events.add(
        SessionUsageEvent(
          requestId: 'claude:$messageId',
          cli: CliTool.claude,
          model: '${message['model'] ?? ''}',
          inputTokens: input,
          outputTokens: output,
          cacheReadTokens: cacheRead,
          cacheCreationTokens: cacheCreate,
          cacheCreation1hTokens: cache1h.clamp(0, cacheCreate),
          inputSemantics: UsageInputSemantics.fresh,
          timestampMs: _timestampMs(obj['timestamp']),
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
          isFinal: stopReason != null && '$stopReason'.trim().isNotEmpty,
        ),
      );
    }
    return UsageScanResult(
      events: events,
      nextCursor: window.nextCursor,
      partialTail: window.partialTail,
      skippedLines: skipped,
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
