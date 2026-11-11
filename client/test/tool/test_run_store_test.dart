import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_run_store.dart';

void main() {
  late Directory tempDir;
  late TestRunStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('test_run_store');
    store = TestRunStore(tempDir);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<TestRunRecord> start({
    List<String> args = const [],
    String selectionKey = '',
    String scope = 'full',
    String headSha = 'HEAD',
    bool treeDirty = true,
    String lockHash = 'LOCK',
    DateTime? now,
  }) {
    return store.startRun(
      args: args,
      selectionKey: selectionKey,
      scope: scope,
      headSha: headSha,
      treeDirty: treeDirty,
      lockHash: lockHash,
      now: now,
    );
  }

  group('selection helpers', () {
    test('empty args are a full run with an empty selection key', () {
      expect(selectionKeyFor(const []), '');
      expect(classifyScope(const []), 'full');
    });

    test('path selectors are scoped', () {
      expect(classifyScope(const ['test/services/git/']), 'scoped');
      expect(classifyScope(const ['--plain-name', 'reclaim']), 'scoped');
    });

    test('tag selectors are integration', () {
      expect(
        classifyScope(const ['--tags', 'integration && docker']),
        'integration',
      );
      expect(classifyScope(const ['--tags=integration']), 'integration');
    });

    test('selection key distinguishes different args', () {
      expect(
        selectionKeyFor(const ['a']),
        isNot(selectionKeyFor(const ['b'])),
      );
    });
  });

  test('startRun records a running entry and updates the current pointer',
      () async {
    final record = await start(now: DateTime(2026, 11, 11, 10));
    final loaded = await store.recordById(record.id);
    expect(loaded, isNotNull);
    expect(loaded!.status, TestRunStatus.running);
    expect(loaded.endedAt, isNull);
    expect(await store.currentId(), record.id);
    expect(loaded.logPath, endsWith('.log'));
    expect(await store.currentRunning(), isNotNull);
  });

  test('finishRun updates status, exit code, and end time', () async {
    final record = await start(now: DateTime(2026, 11, 11, 10));
    await store.finishRun(
      record.id,
      status: TestRunStatus.passed,
      exitCode: 0,
      now: DateTime(2026, 11, 11, 10, 1),
    );
    final loaded = await store.recordById(record.id);
    expect(loaded!.status, TestRunStatus.passed);
    expect(loaded.exitCode, 0);
    expect(loaded.endedAt, DateTime(2026, 11, 11, 10, 1));
    expect(await store.currentRunning(), isNull);
  });

  test('records round-trip through JSON', () async {
    final record = await start(
      args: const ['--plain-name', 'reclaim'],
      selectionKey: 'k',
      scope: 'scoped',
      headSha: 'HEAD1234',
      treeDirty: false,
      lockHash: 'LOCK1234',
    );
    final loaded = await store.recordById(record.id);
    expect(loaded!.args, record.args);
    expect(loaded.selectionKey, record.selectionKey);
    expect(loaded.scope, record.scope);
    expect(loaded.headSha, record.headSha);
    expect(loaded.treeDirty, record.treeDirty);
    expect(loaded.lockHash, record.lockHash);
  });

  test('recentRuns sorts newest first', () async {
    final older = await start(now: DateTime(2026, 11, 11, 9));
    final newer = await start(now: DateTime(2026, 11, 11, 10));
    final records = await store.recentRuns();
    expect(records.map((r) => r.id).toList(), [newer.id, older.id]);
  });

  group('findReusable', () {
    final now = DateTime(2026, 11, 11, 12);

    TestRunRecord passed({
      required DateTime endedAt,
      String head = 'HEAD',
      bool dirty = false,
      String lock = 'LOCK',
      String scope = 'full',
      String selection = '',
    }) {
      return TestRunRecord(
        id: 'run',
        pid: 1,
        host: 'host',
        args: const [],
        selectionKey: selection,
        scope: scope,
        headSha: head,
        treeDirty: dirty,
        lockHash: lock,
        startedAt: endedAt.subtract(const Duration(minutes: 1)),
        endedAt: endedAt,
        status: TestRunStatus.passed,
        exitCode: 0,
        logPath: 'run.log',
      );
    }

    test('matches a fresh clean green full run at the same head and lock', () {
      final hit = store.findReusable(
        candidates: [passed(endedAt: now.subtract(const Duration(minutes: 5)))],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'LOCK',
        now: now,
      );
      expect(hit, isNotNull);
    });

    test('rejects stale results', () {
      final hit = store.findReusable(
        candidates: [passed(endedAt: now.subtract(const Duration(hours: 2)))],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'LOCK',
        now: now,
        maxAge: const Duration(minutes: 30),
      );
      expect(hit, isNull);
    });

    test('rejects dirty producer runs', () {
      final hit = store.findReusable(
        candidates: [passed(endedAt: now, dirty: true)],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'LOCK',
        now: now,
      );
      expect(hit, isNull);
    });

    test('rejects a mismatched head', () {
      final hit = store.findReusable(
        candidates: [passed(endedAt: now)],
        selectionKey: '',
        headSha: 'OTHER',
        lockHash: 'LOCK',
        now: now,
      );
      expect(hit, isNull);
    });

    test('rejects a mismatched lock hash', () {
      final hit = store.findReusable(
        candidates: [passed(endedAt: now)],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'OTHER',
        now: now,
      );
      expect(hit, isNull);
    });

    test('rejects scoped producers', () {
      final hit = store.findReusable(
        candidates: [passed(endedAt: now, scope: 'scoped')],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'LOCK',
        now: now,
      );
      expect(hit, isNull);
    });

    test('rejects failed runs', () {
      final failed = TestRunRecord(
        id: 'failed',
        pid: 1,
        host: 'host',
        args: const [],
        selectionKey: '',
        scope: 'full',
        headSha: 'HEAD',
        treeDirty: false,
        lockHash: 'LOCK',
        startedAt: now,
        endedAt: now,
        status: TestRunStatus.failed,
        exitCode: 1,
        logPath: 'failed.log',
      );
      final hit = store.findReusable(
        candidates: [failed],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'LOCK',
        now: now,
      );
      expect(hit, isNull);
    });

    test('picks the newest qualifying run', () {
      final older = passed(endedAt: now.subtract(const Duration(minutes: 10)));
      final newer = passed(endedAt: now.subtract(const Duration(minutes: 2)));
      final hit = store.findReusable(
        candidates: [older, newer],
        selectionKey: '',
        headSha: 'HEAD',
        lockHash: 'LOCK',
        now: now,
      );
      expect(hit!.id, newer.id);
    });
  });

  test('prune removes old records and their logs', () async {
    final old = await start(now: DateTime(2020));
    await store.finishRun(
      old.id,
      status: TestRunStatus.passed,
      exitCode: 0,
      now: DateTime(2020),
    );
    File(old.logPath).writeAsStringSync('log');

    await store.prune(
      now: DateTime(2026, 11, 11),
      maxAge: const Duration(days: 7),
    );

    expect(await store.recordById(old.id), isNull);
    expect(File(old.logPath).existsSync(), isFalse);
  });
}
