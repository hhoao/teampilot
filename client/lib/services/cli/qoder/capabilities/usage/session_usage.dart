import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';

/// Qoder native usage.
///
/// `QODER_CONFIG_DIR` isolates the CLI's config dir for ACP launches, and the
/// CLI writes its native transcripts to `<configDir>/projects/**/*.jsonl`.
/// Each assistant response carries `message.usage` (input/output tokens plus
/// cache read/creation) and the model it actually used. The same usage may be
/// attached to more than one JSONL record, so requests are deduped by
/// `message.id` (falling back to the record `uuid`).
final class QoderSessionUsageCapability implements SessionUsageCapability {
  const QoderSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final path = ctx.fs.pathContext;
    final configDir = ctx.env['QODER_CONFIG_DIR']?.trim() ?? '';
    final roots = <String>{
      if (configDir.isNotEmpty) configDir,
      if (configDir.isEmpty) ...ctx.transcriptRoots,
    };
    final ids = {
      for (final id in [ctx.nativeSessionId, ctx.taskId])
        if (id.trim().isNotEmpty) id.trim(),
    };

    final out = <SessionUsageSource>[];
    final seen = <String>{};
    for (final root in roots) {
      final projects = path.join(root, 'projects');
      if (!(await ctx.fs.stat(projects)).isDirectory) continue;
      for (final entry in await ctx.fs.listDirRecursive(projects)) {
        if (entry.isDirectory) continue;
        final full = path.join(projects, entry.name);
        final basename = path.basename(entry.name);
        if (!basename.endsWith('.jsonl')) continue;
        if (configDir.isEmpty && ids.isNotEmpty) {
          final segments = path.split(entry.name);
          final owned = ids.any(
            (id) =>
                basename == '$id.jsonl' ||
                (segments.length > 1 && segments.skip(1).contains(id)),
          );
          if (!owned) continue;
        }
        if (!seen.add(full)) continue;
        out.add(
          SessionUsageSource(
            id: 'qoder-jsonl:$full',
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
    final eventsById = <String, SessionUsageEvent>{};
    var skipped = 0;
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
      final usage = _usageOf(obj);
      if (usage == null) continue;
      final model = _modelOf(obj);
      final messageId = _messageIdOf(obj)?.trim() ?? '';
      if (messageId.isEmpty) {
        skipped++;
        continue;
      }
      final tokens = _tokensOf(usage);
      if (tokens.totalBillable == 0) continue;
      final requestId = 'qoder:$messageId';
      final event = SessionUsageEvent(
        requestId: requestId,
        cli: CliTool.qoder,
        model: model,
        inputTokens: tokens.input,
        outputTokens: tokens.output,
        cacheReadTokens: tokens.cacheRead,
        cacheCreationTokens: tokens.cacheCreation,
        // Qoder writes Anthropic-style usage: `input_tokens` already excludes
        // the cache fields, so it is fresh input, not a cached-inclusive total.
        inputSemantics: UsageInputSemantics.fresh,
        timestampMs: _timestampMs(obj['timestamp']),
        sessionId: ctx.sessionId,
        memberId: ctx.memberId,
        teamId: ctx.teamId,
      );
      final previous = eventsById[requestId];
      if (previous == null ||
          tokens.totalBillable >
              previous.inputTokens +
                  previous.outputTokens +
                  previous.cacheReadTokens +
                  previous.cacheCreationTokens ||
          (previous.model.isEmpty && event.model.isNotEmpty)) {
        eventsById[requestId] = event;
      }
    }
    return UsageScanResult(
      events: eventsById.values.toList(growable: false),
      nextCursor: window.nextCursor,
      partialTail: window.partialTail,
      skippedLines: skipped,
    );
  }
}

Map<String, Object?>? _usageOf(Map<String, Object?> obj) {
  final message = obj['message'];
  if (message is Map) {
    final usage = message['usage'];
    if (usage is Map && usage.isNotEmpty) {
      return Map<String, Object?>.from(usage);
    }
  }
  return null;
}

String _modelOf(Map<String, Object?> obj) {
  final message = obj['message'];
  if (message is Map) {
    final value = message['model']?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String? _messageIdOf(Map<String, Object?> obj) {
  final message = obj['message'];
  if (message is Map) {
    final value = message['id']?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  final uuid = obj['uuid']?.toString().trim() ?? '';
  return uuid.isEmpty ? null : uuid;
}

class _Tokens {
  const _Tokens({
    required this.input,
    required this.output,
    required this.cacheRead,
    required this.cacheCreation,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheCreation;

  int get totalBillable => input + output + cacheRead + cacheCreation;
}

_Tokens _tokensOf(Map<String, Object?> raw) => _Tokens(
  input: _int(raw['input_tokens']),
  output: _int(raw['output_tokens']),
  cacheRead: _int(raw['cache_read_input_tokens']),
  cacheCreation: _int(raw['cache_creation_input_tokens']),
);

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

int _timestampMs(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}
