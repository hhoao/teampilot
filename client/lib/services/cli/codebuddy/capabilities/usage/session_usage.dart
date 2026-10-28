import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';

/// CodeBuddy Code native usage.
///
/// `CODEBUDDY_CONFIG_DIR` points at the session tool dir for ACP launches, and
/// the CLI writes its native transcripts to `<configDir>/projects/**/*.jsonl`.
/// Each assistant response carries `providerData.rawUsage` (OpenAI-style
/// prompt/completion tokens) and the model it actually used. The same usage may
/// be attached to more than one JSONL record, so requests are deduped by
/// `providerData.messageId`.
final class CodebuddySessionUsageCapability implements SessionUsageCapability {
  const CodebuddySessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final path = ctx.fs.pathContext;
    final configDir = ctx.env['CODEBUDDY_CONFIG_DIR']?.trim() ?? '';
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
            id: 'codebuddy-jsonl:$full',
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
      final requestId = 'codebuddy:$messageId';
      final event = SessionUsageEvent(
        requestId: requestId,
        cli: CliTool.codebuddy,
        model: model,
        inputTokens: tokens.input,
        outputTokens: tokens.output,
        cacheReadTokens: tokens.cacheRead,
        cacheCreationTokens: tokens.cacheCreation,
        inputSemantics: UsageInputSemantics.total,
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
  final provider = obj['providerData'];
  if (provider is Map) {
    final map = Map<String, Object?>.from(provider);
    final raw = map['rawUsage'];
    if (raw is Map && raw.isNotEmpty) {
      return Map<String, Object?>.from(raw);
    }
    final usage = map['usage'];
    if (usage is Map && usage.isNotEmpty) {
      return Map<String, Object?>.from(usage);
    }
  }
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
  final provider = obj['providerData'];
  if (provider is Map) {
    final map = Map<String, Object?>.from(provider);
    for (final key in const ['model', 'requestModelId', 'requestModelName']) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
  }
  final message = obj['message'];
  if (message is Map) {
    final value = message['model']?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String? _messageIdOf(Map<String, Object?> obj) {
  final provider = obj['providerData'];
  if (provider is Map) {
    final map = Map<String, Object?>.from(provider);
    for (final key in const ['messageId', 'conversationRequestId']) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
  }
  return obj['id']?.toString();
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

_Tokens _tokensOf(Map<String, Object?> raw) {
  final input = _int(
    raw['prompt_tokens'] ?? raw['inputTokens'] ?? raw['input_tokens'],
  );
  final output = _int(
    raw['completion_tokens'] ?? raw['outputTokens'] ?? raw['output_tokens'],
  );
  final promptDetails = raw['prompt_tokens_details'];
  final inputDetails = raw['inputTokensDetails'];
  final cached = _firstNonZero([
    _int(raw['prompt_cache_hit_tokens']),
    _int(raw['cache_read_input_tokens']),
    _int(raw['cacheReadTokens']),
    _int(raw['cached_tokens']),
    if (promptDetails is Map) _int(promptDetails['cached_tokens']),
    if (inputDetails is List &&
        inputDetails.isNotEmpty &&
        inputDetails.first is Map)
      _int((inputDetails.first as Map)['cached_tokens']),
  ]);
  final cacheCreation = _firstNonZero([
    _int(raw['cache_creation_input_tokens']),
    _int(raw['prompt_cache_write_tokens']),
    _int(raw['cacheWriteTokens']),
  ]);
  return _Tokens(
    input: input,
    output: output,
    cacheRead: cached,
    cacheCreation: cacheCreation,
  );
}

int _firstNonZero(Iterable<int> values) {
  for (final value in values) {
    if (value != 0) return value;
  }
  return 0;
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

int _timestampMs(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}
