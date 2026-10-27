import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/opencode/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../../../../support/opencode_v2_sqlite.dart';

void main() {
  late Directory base;
  late String dbPath;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_usage_');
    dbPath = p.join(base.path, 'opencode.db');
  });

  tearDown(() async {
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
    if (await base.exists()) await base.delete(recursive: true);
  });

  UsageScanContext ctx() => UsageScanContext(
    fs: fs,
    cli: CliTool.opencode,
    env: {'OPENCODE_DB': dbPath},
    transcriptRoots: const [],
    taskId: 'task-1',
    nativeSessionId: 'ses_1',
    sessionId: 's1',
    memberId: 'dev',
    teamId: 'team1',
    workingDirectory: '/home/me/proj',
    appDataRoot: '/tp',
  );

  void writeAssistant({
    required String id,
    required int seq,
    required Map<String, Object?> tokens,
    String model = 'claude-sonnet-4',
    int timeCreated = 1000,
    int? timeUpdated,
    double? cost,
  }) {
    final db = sqlite3.open(dbPath);
    try {
      final hasSchema = db
          .select(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' "
            "AND name = 'session_message' LIMIT 1",
          )
          .isNotEmpty;
      if (!hasSchema) createOpencodeV2Schema(db);
      db.execute(
        'INSERT OR REPLACE INTO session_message '
        '(id, session_id, type, seq, time_created, time_updated, data) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          'ses_1',
          'assistant',
          seq,
          timeCreated,
          timeUpdated ?? timeCreated,
          jsonEncode({
            'role': 'assistant',
            'model': {'id': model},
            'tokens': tokens,
            if (cost != null) 'cost': cost,
            'time': {'created': timeCreated},
          }),
        ],
      );
    } finally {
      db.close();
    }
  }

  test('discovers the seat database', () async {
    writeAssistant(id: 'msg_1', seq: 1, tokens: {'input': 10, 'output': 2});

    final sources = await const OpencodeSessionUsageCapability()
        .discoverUsageSources(ctx());

    expect(sources, hasLength(1));
    expect(sources.single.kind, UsageSourceKind.sqlite);
    expect(sources.single.path, dbPath);
  });

  test('parses fresh input, reasoning, cache, and cost', () async {
    writeAssistant(
      id: 'msg_1',
      seq: 1,
      tokens: {
        'input': 100,
        'output': 20,
        'reasoning': 5,
        'cache': {'read': 30, 'write': 10},
      },
      cost: 0.012345,
    );
    final source =
        (await const OpencodeSessionUsageCapability().discoverUsageSources(
          ctx(),
        )).single;

    final scan = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );

    final event = scan.events.single;
    expect(event.requestId, 'opencode:msg_1');
    expect(event.inputTokens, 100);
    expect(event.outputTokens, 25);
    expect(event.cacheReadTokens, 30);
    expect(event.cacheCreationTokens, 10);
    expect(event.inputSemantics, UsageInputSemantics.fresh);
    expect(event.costMicroUsd, 12345);
    expect(event.model, 'claude-sonnet-4');
  });

  test('skips user and zero-token messages', () async {
    final db = sqlite3.open(dbPath);
    try {
      createOpencodeV2Schema(db);
      insertOpencodeV2User(
        db,
        id: 'msg_user',
        sessionId: 'ses_1',
        seq: 1,
        text: 'hi',
      );
      db.execute(
        'INSERT INTO session_message '
        '(id, session_id, type, seq, time_created, time_updated, data) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'msg_zero',
          'ses_1',
          'assistant',
          2,
          1000,
          1000,
          jsonEncode({
            'role': 'assistant',
            'tokens': {'input': 0, 'output': 0},
          }),
        ],
      );
    } finally {
      db.close();
    }
    final source =
        (await const OpencodeSessionUsageCapability().discoverUsageSources(
          ctx(),
        )).single;

    final scan = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );

    expect(scan.events, isEmpty);
  });

  test('returns nothing when the snapshot token is unchanged', () async {
    writeAssistant(id: 'msg_1', seq: 1, tokens: {'input': 10, 'output': 2});
    final source =
        (await const OpencodeSessionUsageCapability().discoverUsageSources(
          ctx(),
        )).single;
    final first = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );
    final second = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: first.nextCursor,
    );

    expect(first.events, hasLength(1));
    expect(second.events, isEmpty);
    expect(second.nextCursor.storeToken, first.nextCursor.storeToken);
  });

  test('reads only new and updated messages after the snapshot', () async {
    writeAssistant(id: 'msg_1', seq: 1, tokens: {'input': 10, 'output': 2});
    final source =
        (await const OpencodeSessionUsageCapability().discoverUsageSources(
          ctx(),
        )).single;
    final first = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );

    writeAssistant(
      id: 'msg_2',
      seq: 2,
      timeCreated: 2000,
      tokens: {'input': 20, 'output': 3},
    );
    final second = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events, hasLength(1));
    expect(second.events.single.requestId, 'opencode:msg_2');

    writeAssistant(
      id: 'msg_1',
      seq: 1,
      timeCreated: 1000,
      timeUpdated: 3000,
      tokens: {'input': 10, 'output': 4},
      cost: 0.5,
    );
    final third = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: second.nextCursor,
    );

    expect(third.events, hasLength(1));
    expect(third.events.single.requestId, 'opencode:msg_1');
    expect(third.events.single.costMicroUsd, 500000);
  });
}
