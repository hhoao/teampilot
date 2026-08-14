import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';

/// opencode SQLite 查询函数签名。
///
/// 必须是**顶层或静态**函数(闭包不可跨 isolate 发送),[args] 为可发送参数。
typedef SqliteQueryFn = Object? Function(Database db, Object? args);

/// opencode SQLite 常驻 worker 池:每个 dbPath 一个长驻 isolate + 一个
/// 常驻只读连接,查询走消息队列。
///
/// 相比每次查询 `Isolate.run` + `sqlite3.open`:
///  - 消除每次 spawn(~1-5ms)与 40MB+ WAL 库的重复 open(最重的成本);
///  - 连接级页面缓存跨查询保持热,重复查询不再重新读页;
///  - isolate 单线程天然串行,同库查询永不并发。
///
/// worker 空闲 [idleTimeout] 后自动关闭连接退出,下一次查询按需重拉;
/// 也可在会话关闭时显式 [dispose]。
///
/// 防挂死:单条查询超过 [queryTimeout] 客户端强制失败并弃用该 worker
/// (下次查询按需重建);worker 空闲退出时所有在途查询立即失败。二者都
/// 保证一次瞬时卡顿只会表现为可重试的查询失败,绝不让 seat 的
/// `正在加载对话历史` 永久停在 loading。
class OpencodeSqliteWorkerPool {
  OpencodeSqliteWorkerPool._();

  static final OpencodeSqliteWorkerPool instance = OpencodeSqliteWorkerPool._();

  /// worker 空闲时长(超过则关闭连接退出,下次查询按需重拉)。
  /// 测试可缩短以验证空闲回收。
  Duration idleTimeout = const Duration(seconds: 30);

  /// 单条查询客户端超时:worker 不响应(原生池卡死 / FFI 阻塞 / 队列
  /// 堆积)时强制失败,而不是无限等待。90MB 级大库全量 locate 实测
  /// 百毫秒级,30s 对慢速磁盘/远程快照也足够宽裕。
  Duration queryTimeout = const Duration(seconds: 30);

  final Map<String, _SqliteWorker> _workers = {};

  Future<T?> run<T>({
    required String dbPath,
    required SqliteQueryFn query,
    Object? args,
  }) async {
    var worker = _workers[dbPath];
    if (worker == null || worker.isDead) {
      worker = _SqliteWorker(dbPath, idleTimeout, queryTimeout);
      _workers[dbPath] = worker;
    }
    return worker.run<T>(query, args);
  }

  /// 显式回收(会话关闭时调用)。
  void dispose(String dbPath) {
    _workers.remove(dbPath)?.close();
  }

  @visibleForTesting
  int get liveWorkerCount => _workers.length;
}

/// 单 dbPath 的 worker 客户端:负责 spawn 与请求/响应协议。
class _SqliteWorker {
  _SqliteWorker(this.dbPath, this.idleTimeout, this.queryTimeout) {
    _init();
  }

  final String dbPath;
  final Duration idleTimeout;
  final Duration queryTimeout;

  final _pending = <int, Completer<Object?>>{};
  final _responses = ReceivePort();
  final _control = ReceivePort();
  int _nextRequestId = 0;
  SendPort? _requestPort;
  Future<Isolate>? _isolateFuture;
  bool _failed = false;
  bool _exited = false;

  /// worker 已死(空闲退出/spawn 失败/显式关闭/查询超时弃用)→ 池中条目下次 run 时替换。
  bool get isDead => _failed || _exited;

  void _init() {
    _isolateFuture = Isolate.spawn(
      _sqliteWorkerEntry,
      _SpawnArgs(
        dbPath: dbPath,
        control: _control.sendPort,
        responses: _responses.sendPort,
        idleTimeoutMillis: idleTimeout.inMilliseconds,
      ),
      debugName: 'opencode-sqlite-read',
      onError: _control.sendPort,
    );
    _responses.listen(_onResponse);
    _control.listen(_onControl);
  }

  Future<T?> run<T>(SqliteQueryFn query, Object? args) {
    final port = _requestPort;
    if (port == null) {
      // worker 尚未就绪(首次 spawn)。若已失败则抛出,由池重建。
      if (isDead) {
        throw StateError('opencode sqlite worker dead for $dbPath');
      }
      return _waitReady().then(
        (readyPort) =>
            readyPort == null ? null as T? : _send<T>(readyPort, query, args),
      );
    }
    return _send<T>(port, query, args);
  }

  /// 等 ready 消息(SendPort),限时避免永久等待。
  Future<SendPort?> _waitReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_requestPort == null && !isDead) {
      if (DateTime.now().isAfter(deadline)) {
        _kill(
          TimeoutException('opencode sqlite worker not ready: $dbPath'),
        );
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _requestPort;
  }

  Future<T?> _send<T>(SendPort port, SqliteQueryFn query, Object? args) async {
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    port.send(_QueryRequest(requestId: requestId, query: query, args: args));
    try {
      final result = await completer.future.timeout(queryTimeout);
      return result as T?;
    } on TimeoutException catch (e) {
      // 查询永久卡住(原生池/FFI 阻塞或队列堆积):失败本查询,并弃用
      // 该 worker,让下一次查询按需重建。绝不让调用方无限等待。
      _pending.remove(requestId);
      _kill(e);
      rethrow;
    }
  }

  /// 弃用 worker:失败所有在途查询、关闭端口,并尽力关闭原生池与
  /// isolate(被 FFI 阻塞时 kill 是尽力而为,无法打断原生调用)。
  void _kill(Object error) {
    if (isDead) return;
    _failed = true;
    _failAllPending(error);
    _control.close();
    _responses.close();
    // 告知 worker 关闭原生池(优雅路径;worker 正在执行查询时会在其
    // 结束后处理)。同名再开再关也会命中已存在的池,清理旧的原生池,
    // 避免新 worker 重新挂到坏池上。
    try {
      _requestPort?.send(const _CloseRequest());
    } on Object {
      // best-effort
    }
    try {
      _isolateFuture?.then(
        (isolate) => isolate.kill(priority: Isolate.immediate),
      );
    } on Object {
      // best-effort
    }
  }

  void _onControl(Object? message) {
    if (message is SendPort) {
      _requestPort = message;
      return;
    }
    if (message is _SpawnError) {
      _failed = true;
      _failAllPending(message.error, message.stackTrace);
      return;
    }
    if (message is List && message.length == 2) {
      // Isolate.spawn(onError) → [error, stackTrace]。
      _failed = true;
      _failAllPending(message[0], message[1] as StackTrace?);
    }
  }

  void _onResponse(Object? message) {
    if (message is _WorkerExited) {
      // worker 空闲退出(连接已关闭):在途查询永远不会得到响应,
      // 必须立即失败,否则调用方永久等待。
      _exited = true;
      _failAllPending(
        StateError('opencode sqlite worker exited before answering: $dbPath'),
        null,
      );
      return;
    }
    final response = message as _QueryResponse;
    final completer = _pending.remove(response.requestId);
    completer?.complete(response.result);
  }

  void _failAllPending(Object error, [StackTrace? st]) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error, st);
    }
  }

  void close() {
    _exited = true;
    // 通知 worker 关池退出(而不是等空闲超时),再断开客户端端口。
    _requestPort?.send(const _CloseRequest());
    _control.close();
    _responses.close();
    _failAllPending(StateError('opencode sqlite worker closed: $dbPath'), null);
  }
}

class _SpawnArgs {
  const _SpawnArgs({
    required this.dbPath,
    required this.control,
    required this.responses,
    required this.idleTimeoutMillis,
  });

  final String dbPath;
  final SendPort control;
  final SendPort responses;
  final int idleTimeoutMillis;
}

class _QueryRequest {
  const _QueryRequest({
    required this.requestId,
    required this.query,
    required this.args,
  });

  final int requestId;
  final SqliteQueryFn query;
  final Object? args;
}

class _QueryResponse {
  const _QueryResponse(this.requestId, this.result);

  final int requestId;
  final Object? result;
}

class _SpawnError {
  const _SpawnError(this.error, this.stackTrace);

  final Object error;
  final StackTrace? stackTrace;
}

class _WorkerExited {
  const _WorkerExited();
}

/// Worker 入口(顶层函数,可被 Isolate.spawn):连接由官方
/// [SqliteConnectionPool] 托管(每个 dbPath 一个 Rust 全局池,连接跨查询
/// 保持热、可并行读),本 worker 作为"非 UI isolate 宿主"执行查询块
/// (多 SELECT + 片段拼装)与租约管理,空闲超时后关池退出。
void _sqliteWorkerEntry(_SpawnArgs args) {
  final SqliteConnectionPool pool;
  try {
    pool = SqliteConnectionPool.open(
      name: args.dbPath,
      openConnections: () {
        final writer = _openReadOnlyConnection(args.dbPath);
        final reader = _openReadOnlyConnection(args.dbPath);
        return PoolConnections(
          writer,
          [reader],
          // 指纹/计数查询重复执行,LRU 语句缓存避免重复 prepare。
          preparedStatementCacheSize: 16,
        );
      },
    );
  } on Object catch (error, st) {
    args.control.send(_SpawnError(error, st));
    return;
  }

  final requests = ReceivePort();
  args.control.send(requests.sendPort); // ready

  Timer? idleTimer;
  void armIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(Duration(milliseconds: args.idleTimeoutMillis), () {
      args.responses.send(const _WorkerExited());
      requests.close();
      pool.close();
    });
  }

  armIdleTimer();
  // 异步租约要求串行队列:同一时刻最多一个查询块在跑。
  Future<void> chain = Future<void>.value();
  requests.listen((message) {
    if (message is _QueryRequest) {
      chain = chain.then((_) => _handleQuery(args, pool, message));
      return;
    }
    if (message is _CloseRequest) {
      pool.close();
      requests.close();
    }
  });
}

Database _openReadOnlyConnection(String dbPath) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  db.execute('PRAGMA query_only = true');
  return db;
}

/// 在 worker isolate 上执行一个查询块:从池租连接 → 在
/// [ConnectionLease.unsafeAccess] 临界区内同步跑 [SqliteQueryFn]
/// (多 SELECT + 拼装)→ 还租。失败 → null。
Future<void> _handleQuery(
  _SpawnArgs args,
  SqliteConnectionPool pool,
  _QueryRequest message,
) async {
  Object? result;
  ConnectionLease? lease;
  try {
    lease = await pool.reader();
    result = await lease.unsafeAccess(
      (connection) => message.query(connection.database, message.args),
    );
  } on Object {
    // 与旧 Isolate.run 语义一致:查询失败 → null,不抛出。
    result = null;
  } finally {
    lease?.returnLease();
  }
  args.responses.send(_QueryResponse(message.requestId, result));
}

/// 显式关池请求(客户端 dispose 时发送,worker 立即关池退出)。
class _CloseRequest {
  const _CloseRequest();
}
