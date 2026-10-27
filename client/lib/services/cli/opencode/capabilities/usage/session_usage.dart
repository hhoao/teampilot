import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../native_session_id.dart';
import '../sqlite_worker_pool.dart';

final class OpencodeSessionUsageCapability implements SessionUsageCapability {
  const OpencodeSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final dbPath = ctx.env['OPENCODE_DB']?.trim() ?? '';
    if (dbPath.isEmpty) return const [];
    if (!(await ctx.fs.stat(dbPath)).isFile) return const [];
    return [
      SessionUsageSource(
        id: 'opencode-sqlite:$dbPath',
        path: dbPath,
        kind: UsageSourceKind.sqlite,
        sessionId: ctx.sessionId,
        memberId: ctx.memberId,
        teamId: ctx.teamId,
      ),
    ];
  }

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    final handle = await resolveOpencodeSqliteReadPath(
      fs: ctx.fs,
      dbPath: source.path,
    );
    if (handle == null) {
      return UsageScanResult(
        events: const [],
        nextCursor: cursor ?? UsageCursor.empty,
      );
    }

    final snapshot = _parseSnapshotToken(cursor?.storeToken);
    final result = await OpencodeSqliteWorkerPool.instance
        .run<Map<String, Object?>>(
          dbPath: handle.path,
          query: _readUsageRows,
          args: {
            'sinceTime': snapshot?.time ?? 0,
            'sinceSeq': snapshot?.seq ?? -1,
          },
        );
    if (result == null) {
      throw StateError('opencode usage query failed: ${source.path}');
    }
    final token = '${result['token'] ?? ''}';
    if (cursor?.storeToken == token) {
      return UsageScanResult(events: const [], nextCursor: cursor!);
    }

    final rows = (result['rows'] as List?) ?? const [];
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    var rowIndex = 0;
    for (final raw in rows) {
      if (rowIndex++ % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      if (raw is! Map) continue;
      final row = Map<String, Object?>.from(raw);
      final dataRaw = row['data'];
      Map<String, Object?>? data;
      try {
        final decoded = jsonDecode('${dataRaw ?? ''}');
        if (decoded is Map) data = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (data == null) {
        skipped++;
        continue;
      }
      final isAssistant =
          row['type'] == 'assistant' || data['role'] == 'assistant';
      if (!isAssistant) continue;
      final tokensRaw = data['tokens'];
      if (tokensRaw is! Map) continue;
      final tokens = Map<String, Object?>.from(tokensRaw);
      final input = _int(tokens['input']);
      final output = _int(tokens['output']);
      final reasoning = _int(tokens['reasoning']);
      final cacheRaw = tokens['cache'];
      final cache = cacheRaw is Map
          ? Map<String, Object?>.from(cacheRaw)
          : const <String, Object?>{};
      final cacheRead = _int(cache['read']);
      final cacheWrite = _int(cache['write']);
      if (input == 0 &&
          output == 0 &&
          reasoning == 0 &&
          cacheRead == 0 &&
          cacheWrite == 0) {
        continue;
      }
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final cost = data['cost'];
      events.add(
        SessionUsageEvent(
          requestId: 'opencode:$id',
          cli: CliTool.opencode,
          model: _modelFrom(data),
          inputTokens: input,
          outputTokens: output + reasoning,
          cacheReadTokens: cacheRead,
          cacheCreationTokens: cacheWrite,
          inputSemantics: UsageInputSemantics.fresh,
          timestampMs: _timestampMs(data, row),
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
          isFinal: true,
          costMicroUsd: cost is num ? (cost * 1000000).round() : null,
        ),
      );
    }

    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(storeToken: token),
      skippedLines: skipped,
    );
  }
}

/// V2 `session_message` first, legacy V1 `message` second.
///
/// Top-level function: runs in the OpenCode SQLite worker isolate.
Map<String, Object?>? _readUsageRows(Database db, Object? args) {
  final argMap = args is Map
      ? Map<String, Object?>.from(args)
      : const <String, Object?>{};
  final sinceTime = (argMap['sinceTime'] as num?)?.toInt() ?? 0;
  final sinceSeq = (argMap['sinceSeq'] as num?)?.toInt() ?? -1;

  final v2 = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'session_message' LIMIT 1",
  );
  if (v2.isNotEmpty) {
    final columns = db.select('PRAGMA table_info(session_message)');
    final hasSeq = columns.any((row) => row['name'] == 'seq');
    final hasUpdated = columns.any((row) => row['name'] == 'time_updated');
    final timeColumn = hasUpdated ? 'time_updated' : 'time_created';
    final maxRow = db
        .select(
          'SELECT MAX($timeColumn) AS max_time'
          '${hasSeq ? ', MAX(seq) AS max_seq' : ''} '
          'FROM session_message',
        )
        .first;
    final maxTime = (maxRow['max_time'] as num?)?.toInt() ?? 0;
    final maxSeq = hasSeq ? (maxRow['max_seq'] as num?)?.toInt() ?? -1 : -1;

    final where = hasSeq
        ? 'WHERE seq > ? OR $timeColumn > ?'
        : 'WHERE $timeColumn > ?';
    final params = hasSeq
        ? <Object?>[sinceSeq, sinceTime]
        : <Object?>[sinceTime];
    final rows = db.select(
      'SELECT id, type, data, time_created'
      '${hasUpdated ? ', time_updated' : ''}'
      '${hasSeq ? ', seq' : ''} '
      'FROM session_message '
      '$where '
      'ORDER BY ${hasSeq ? 'seq ASC, id ASC' : 'time_created ASC, id ASC'}',
      params,
    );
    return {
      'token': 'oc|2|$maxTime|$maxSeq',
      'rows': [
        for (final row in rows)
          {
            'id': row['id'],
            'type': row['type'],
            'data': row['data'],
            'time_created': row['time_created'],
          },
      ],
    };
  }

  final v1 = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'message' LIMIT 1",
  );
  if (v1.isEmpty) {
    throw StateError('opencode usage: neither session_message nor message');
  }
  final rows = db.select(
    'SELECT id, data, time_created FROM message '
    'ORDER BY time_created ASC, id ASC',
  );
  final maxTime = rows.fold<int>(0, (max, row) {
    final time = row['time_created'];
    return time is num && time.toInt() > max ? time.toInt() : max;
  });
  return {
    'token': 'oc|1|$maxTime|-1',
    'rows': [
      for (final row in rows)
        {
          'id': row['id'],
          'type': null,
          'data': row['data'],
          'time_created': row['time_created'],
        },
    ],
  };
}

final class _SnapshotToken {
  const _SnapshotToken(this.time, this.seq);

  final int time;
  final int seq;
}

_SnapshotToken? _parseSnapshotToken(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split('|');
  if (parts.length != 4 || parts.first != 'oc') return null;
  final time = int.tryParse(parts[2]);
  final seq = int.tryParse(parts[3]);
  if (time == null || seq == null) return null;
  return _SnapshotToken(time, seq);
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

String _modelFrom(Map<String, Object?> data) {
  final direct = data['modelID'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  final model = data['model'];
  if (model is String) return model.trim();
  if (model is Map) return '${model['id'] ?? ''}'.trim();
  return '';
}

int _timestampMs(Map<String, Object?> data, Map<String, Object?> row) {
  final time = data['time'];
  if (time is Map) {
    final created = time['created'];
    if (created is num) return created.toInt();
  }
  final created = row['time_created'];
  return created is num ? created.toInt() : 0;
}
