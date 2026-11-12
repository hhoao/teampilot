import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../grok_constants.dart';

/// Grok (ACP) usage.
///
/// The ACP chat cubit appends one `usage_update` sample per turn to
/// `<sessionToolDir>/acp-usage.jsonl`; `GROK_HOME` points at that same tool
/// dir. `used` is the context in use for the turn, `size` the context window.
final class GrokSessionUsageCapability implements SessionUsageCapability {
  const GrokSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final path = ctx.fs.pathContext;
    final grokHome = ctx.env[GrokConstants.homeEnvKey]?.trim() ?? '';
    final roots = <String>{
      if (grokHome.isNotEmpty) grokHome,
      ...ctx.transcriptRoots,
    };

    final out = <SessionUsageSource>[];
    final seen = <String>{};
    for (final root in roots) {
      if (root.trim().isEmpty) continue;
      final full = path.join(root, GrokConstants.usageFileName);
      if (!(await ctx.fs.stat(full)).isFile) continue;
      if (!seen.add(full)) continue;
      out.add(
        SessionUsageSource(
          id: 'grok-jsonl:$full',
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
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    final startLine =
        (window.nextCursor.lineOffset ?? window.lines.length) -
        window.lines.length;
    for (var i = 0; i < window.lines.length; i++) {
      if (i % 500 == 0) await Future<void>.delayed(Duration.zero);
      final line = window.lines[i].trim();
      if (line.isEmpty) continue;
      Map<String, Object?>? record;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) record = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (record == null) {
        skipped++;
        continue;
      }
      final event = _eventFromRecord(
        ctx: ctx,
        record: record,
        fallbackOrdinal: startLine + i,
      );
      if (event != null) events.add(event);
    }
    return UsageScanResult(
      events: events,
      nextCursor: window.nextCursor,
      partialTail: window.partialTail,
      skippedLines: skipped,
    );
  }

  SessionUsageEvent? _eventFromRecord({
    required UsageScanContext ctx,
    required Map<String, Object?> record,
    required int fallbackOrdinal,
  }) {
    final used = _int(record['used']);
    // `used == 0` is the sample emitted right after `session/new`; it carries
    // no billable context.
    if (used <= 0) return null;
    final sessionId = record['sessionId']?.toString().trim() ?? '';
    final sequence = _int(record['sequence']);
    final requestKey = sequence > 0 ? '$sequence' : 'idx-$fallbackOrdinal';
    final model = record['model']?.toString().trim() ?? '';
    return SessionUsageEvent(
      requestId: '${sessionId.isEmpty ? ctx.sessionId : sessionId}:$requestKey',
      cli: CliTool.grok,
      model: model,
      inputTokens: used,
      outputTokens: 0,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.total,
      timestampMs: sequence > 0 ? sequence ~/ 1000 : 0,
      sessionId: ctx.sessionId,
      memberId: ctx.memberId,
      teamId: ctx.teamId,
    );
  }
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;
