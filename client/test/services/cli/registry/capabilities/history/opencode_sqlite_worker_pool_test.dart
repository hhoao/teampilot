import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';
import 'package:teampilot/services/cli/opencode/capabilities/native_session_id.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';

/// 测试专用查询:失败路径(worker isolate 上抛错 → null)。
String? _boomQuery(Database db, Object? args) {
  throw StateError('boom');
}

/// 测试专用查询:同步忙等 [ms] 毫秒再返回(模拟慢/阻塞查询)。
String? _busyWaitQuery(Database db, Object? args) {
  final ms = (args as int);
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {}
  return 'done';
}

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sqlite-pool-test-');
    dbPath = p.join(tmp.path, 'opencode.db');
    final db = sqlite3.open(dbPath);
    try {
      db.execute('CREATE TABLE session (id TEXT, time_updated INTEGER)');
      db.execute(
        'INSERT INTO session VALUES (?, ?)',
        ['ses_1', 100],
      );
    } finally {
      db.close();
    }
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('runs query on a resident worker and reuses the connection', () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    final first = await pool.run<String?>(
      dbPath: dbPath,
      query: opencodeNewestSessionId,
    );
    expect(first, 'ses_1');
    expect(pool.liveWorkerCount, 1);

    // 第二次查询复用同一 worker(连接缓存保持热),不产生第二个 isolate。
    final second = await pool.run<String?>(
      dbPath: dbPath,
      query: opencodeNewestSessionId,
    );
    expect(second, 'ses_1');
    expect(pool.liveWorkerCount, 1);

    pool.dispose(dbPath);
    expect(pool.liveWorkerCount, 0);
  });

  test('query failure returns null and the worker survives', () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    final failed = await pool.run<String?>(
      dbPath: dbPath,
      query: _boomQuery,
    );
    expect(failed, isNull);

    // 同一 worker 后续查询仍正常。
    final ok = await pool.run<String?>(
      dbPath: dbPath,
      query: opencodeNewestSessionId,
    );
    expect(ok, 'ses_1');
    expect(pool.liveWorkerCount, 1);

    pool.dispose(dbPath);
  });

  test('idle worker exits and is respawned on the next run', () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    pool.idleTimeout = const Duration(milliseconds: 80);
    try {
      final first = await pool.run<String?>(
        dbPath: dbPath,
        query: opencodeNewestSessionId,
      );
      expect(first, 'ses_1');

      await Future<void>.delayed(const Duration(milliseconds: 250));

      // 空闲退出后自动按需重拉,结果一致。
      final second = await pool.run<String?>(
        dbPath: dbPath,
        query: opencodeNewestSessionId,
      );
      expect(second, 'ses_1');
    } finally {
      pool.idleTimeout = const Duration(seconds: 30);
      pool.dispose(dbPath);
    }
  });

  test(
    'worker idle-exit while queries wait on a busy lease fails them '
    'instead of hanging forever',
    () async {
      final pool = OpencodeSqliteWorkerPool.instance;
      pool.idleTimeout = const Duration(milliseconds: 80);
      SqliteConnectionPool? holder;
      ConnectionLease? heldLease;
      try {
        // 先让 worker 把原生池建好(名字=dbPath,进程内全局共享)。
        final first = await pool.run<String?>(
          dbPath: dbPath,
          query: opencodeNewestSessionId,
        );
        expect(first, 'ses_1');

        // 测试侧挂住唯一的 reader lease:worker 的下一个查询只能排队等。
        holder = SqliteConnectionPool.open(
          name: dbPath,
          openConnections: () => throw StateError('pool should already exist'),
        );
        heldLease = await holder.reader();

        // 查询在 worker 上等 lease;worker 空闲超时退出时,挂起的查询必须
        // 失败(而非永久等待)。
        final pending = pool.run<String?>(
          dbPath: dbPath,
          query: opencodeNewestSessionId,
        );
        await expectLater(
          pending.timeout(const Duration(seconds: 10)),
          throwsA(isA<StateError>()),
        );

        // 归还 lease 后,新 worker 正常服务。
        heldLease.returnLease();
        heldLease = null;
        holder.close();
        holder = null;
        final recovered = await pool.run<String?>(
          dbPath: dbPath,
          query: opencodeNewestSessionId,
        );
        expect(recovered, 'ses_1');
      } finally {
        heldLease?.returnLease();
        holder?.close();
        pool.idleTimeout = const Duration(seconds: 30);
        pool.dispose(dbPath);
      }
    },
  );

  test('query timeout fails a stuck query and the next run recovers', () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    final savedTimeout = pool.queryTimeout;
    pool.queryTimeout = const Duration(milliseconds: 200);
    try {
      // 慢查询超过 queryTimeout:客户端必须失败,而不是无限等待。
      await expectLater(
        pool
            .run<String?>(
              dbPath: dbPath,
              query: _busyWaitQuery,
              args: 1500,
            )
            .timeout(const Duration(seconds: 10)),
        throwsA(isA<TimeoutException>()),
      );

      // 失败后新 worker 立即可用。
      final ok = await pool.run<String?>(
        dbPath: dbPath,
        query: opencodeNewestSessionId,
      );
      expect(ok, 'ses_1');
    } finally {
      pool.queryTimeout = savedTimeout;
      pool.dispose(dbPath);
    }
  });
}
