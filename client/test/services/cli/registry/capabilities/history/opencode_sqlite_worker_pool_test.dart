import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/opencode/capabilities/native_session_id.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';

/// 测试专用查询:失败路径(worker isolate 上抛错 → null)。
String? _boomQuery(Database db, Object? args) {
  throw StateError('boom');
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
}
