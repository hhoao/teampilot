import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';
import '../history/root_rollout.dart';

const String _pinToken = 'pin';

final class CodexSessionUsageCapability implements SessionUsageCapability {
  const CodexSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final home = ctx.env['CODEX_HOME']?.trim() ?? '';
    if (home.isEmpty) return const [];
    final path = ctx.fs.pathContext;
    final sessions = path.join(home, 'sessions');
    if (!(await ctx.fs.stat(sessions)).isDirectory) return const [];

    final out = <SessionUsageSource>[];
    for (final entry in await ctx.fs.listDirRecursive(sessions)) {
      if (entry.isDirectory) continue;
      final basename = path.basename(entry.name);
      if (!basename.startsWith('rollout-') || !basename.endsWith('.jsonl')) {
        continue;
      }
      final full = path.join(sessions, entry.name);
      out.add(
        SessionUsageSource(
          id: 'codex-jsonl:$full',
          path: full,
          kind: UsageSourceKind.jsonl,
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
        ),
      );
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
    final path = ctx.fs.pathContext;
    final match = codexRolloutId.firstMatch(path.basename(source.path));
    final threadId =
        match?.group(1) ?? path.basenameWithoutExtension(source.path);

    final resetAfterPin = cursor?.storeToken == _pinToken;
    var baseline = resetAfterPin ? null : _Counters.decode(cursor?.storeToken);
    var nextBaseline = baseline;
    var skipFirstTotal = resetAfterPin;
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    var currentModel = '';

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
      if (obj['type'] == 'turn_context') {
        final payloadRaw = obj['payload'];
        if (payloadRaw is Map) {
          final payload = Map<String, Object?>.from(payloadRaw);
          final model = '${payload['model'] ?? ''}'.trim();
          if (model.isNotEmpty) currentModel = model;
        }
        continue;
      }
      if (obj['type'] != 'event_msg') continue;
      final payloadRaw = obj['payload'];
      if (payloadRaw is! Map) continue;
      final payload = Map<String, Object?>.from(payloadRaw);
      if (payload['type'] != 'token_count') continue;
      final infoRaw = payload['info'];
      if (infoRaw is! Map) continue;
      final info = Map<String, Object?>.from(infoRaw);

      final last = _Counters.fromUsage(info['last_token_usage']);
      final total = _Counters.fromUsage(info['total_token_usage']);
      final _Counters? counters;
      if (last != null && last.anyPositive) {
        counters = last.clamped();
        skipFirstTotal = false;
      } else if (total != null) {
        if (skipFirstTotal) {
          counters = null;
          skipFirstTotal = false;
        } else {
          counters = total.deltaFrom(baseline);
        }
      } else {
        counters = null;
      }
      if (total != null) {
        baseline = total;
        nextBaseline = total;
      }
      if (counters == null || !counters.anyPositive) continue;

      events.add(
        SessionUsageEvent(
          requestId: 'codex:$threadId:${window.lineOffsets[i]}',
          cli: CliTool.codex,
          model: currentModel,
          inputTokens: counters.input,
          outputTokens: counters.output,
          cacheReadTokens: counters.cacheRead,
          cacheCreationTokens: counters.cacheWrite,
          inputSemantics: UsageInputSemantics.total,
          timestampMs: _timestampMs(obj['timestamp']),
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
          isFinal: true,
        ),
      );
    }

    if (window.pinnedToEof) {
      nextBaseline = null;
    }

    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(
        byteOffset: window.nextCursor.byteOffset,
        mtimeMs: window.nextCursor.mtimeMs,
        size: window.nextCursor.size,
        tailFingerprint: window.nextCursor.tailFingerprint,
        lineOffset: window.nextCursor.lineOffset,
        storeToken: window.pinnedToEof ? _pinToken : nextBaseline?.encode(),
      ),
      partialTail: window.partialTail,
      skippedLines: skipped,
    );
  }
}

final class _Counters {
  const _Counters({
    required this.input,
    required this.output,
    required this.cacheRead,
    required this.cacheWrite,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  bool get anyPositive =>
      input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0;

  _Counters clamped() {
    final read = cacheRead.clamp(0, input);
    final write = cacheWrite.clamp(0, input - read);
    return _Counters(
      input: input,
      output: output,
      cacheRead: read,
      cacheWrite: write,
    );
  }

  _Counters? deltaFrom(_Counters? baseline) {
    if (baseline == null) return clamped();
    final next = _Counters(
      input: (input - baseline.input).clamp(0, input),
      output: (output - baseline.output).clamp(0, output),
      cacheRead: (cacheRead - baseline.cacheRead).clamp(0, cacheRead),
      cacheWrite: (cacheWrite - baseline.cacheWrite).clamp(0, cacheWrite),
    );
    return next.anyPositive ? next.clamped() : null;
  }

  String encode() => '$input,$output,$cacheRead,$cacheWrite';

  static _Counters? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(',');
    if (parts.length != 4) return null;
    final values = [for (final part in parts) int.tryParse(part)];
    if (values.any((value) => value == null)) return null;
    return _Counters(
      input: values[0]!,
      output: values[1]!,
      cacheRead: values[2]!,
      cacheWrite: values[3]!,
    );
  }

  static _Counters? fromUsage(Object? raw) {
    if (raw is! Map) return null;
    final input = _int(raw['input_tokens']);
    final cachedRaw = raw['cached_input_tokens'];
    final cacheRead = cachedRaw != null
        ? _int(cachedRaw)
        : _int(raw['cache_read_input_tokens']);
    return _Counters(
      input: input,
      output: _int(raw['output_tokens']),
      cacheRead: cacheRead,
      cacheWrite: _int(raw['cache_write_input_tokens']),
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
