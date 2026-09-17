import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// JSONL 批解码的常驻 worker(全局共享一个实例)。
///
/// 替代每轮 live refresh 一次 `Isolate.run`(spawn + 销毁):JSONL CLI
/// (Claude/Codex/Cursor/FlashskyAI)的 tail 增量刷新每轮都解码新行,
/// 高频场景下消除每次 spawn 成本。worker 无状态(只做解码),
/// 空闲 [idleTimeout] 后退出,下次调用按需重拉。
///
/// Spawn / ready 失败时丢弃 worker 并回退到当前 isolate 同步解码,
/// 避免 Linux debug 下子 isolate 永不 resume 时留下「未 ready 又未 dead」
/// 的僵尸单例(此后所有 session 历史加载都会得到空事件列表)。
class JsonlDecodeWorker {
  JsonlDecodeWorker._();

  static final JsonlDecodeWorker instance = JsonlDecodeWorker._();

  /// worker 空闲时长(测试可缩短以验证空闲回收)。
  Duration idleTimeout = const Duration(seconds: 30);

  /// 等待 worker ready 的最长时间。超时后标死并回退本地解码。
  @visibleForTesting
  Duration readyTimeout = const Duration(seconds: 10);

  _JsonlWorker? _worker;

  Future<List<Map<String, dynamic>?>> decode(List<List<int>> lines) async {
    if (lines.isEmpty) return const [];

    // Large cold transcripts (Codex rollouts can be multi-MB) pay more to
    // copy into the resident worker than they save — decode in-place.
    var totalBytes = 0;
    for (final line in lines) {
      totalBytes += line.length;
      if (totalBytes >= _syncDecodeMinBytes) {
        return decodeJsonlLinesSync(lines);
      }
    }

    final sw = Stopwatch()..start();
    final neededSpawn = _worker == null || _worker!.isDead;
    try {
      final worker = _ensureWorker();
      final result = await worker.decode(lines, readyTimeout: readyTimeout);
      if (kDebugMode && sw.elapsedMilliseconds >= 50) {
        debugPrint(
          '[ai-history-timing] jsonl-decode lines=${lines.length} '
          'spawn=$neededSpawn ms=${sw.elapsedMilliseconds}',
        );
      }
      return result;
    } on TimeoutException {
      _discardWorker();
      return decodeJsonlLinesSync(lines);
    } on StateError {
      _discardWorker();
      return decodeJsonlLinesSync(lines);
    }
  }

  static const _syncDecodeMinBytes = 64 * 1024;

  _JsonlWorker _ensureWorker() {
    final existing = _worker;
    if (existing != null && !existing.isDead) return existing;
    existing?.close();
    final worker = _JsonlWorker(idleTimeout);
    _worker = worker;
    return worker;
  }

  void _discardWorker() {
    final worker = _worker;
    _worker = null;
    worker?.close();
  }

  /// 安装一个永不 ready 的僵尸 worker,用于验证 ready 超时回退。
  @visibleForTesting
  void debugInstallZombieWorker() {
    _discardWorker();
    _worker = _JsonlWorker.zombie();
  }

  @visibleForTesting
  void dispose() {
    _discardWorker();
  }
}

/// 当前 isolate 上同步批解码(worker 不可用时的回退路径)。
List<Map<String, dynamic>?> decodeJsonlLinesSync(List<List<int>> lines) {
  if (lines.isEmpty) return const [];
  return [
    for (final line in lines)
      _tryDecode(utf8.decode(line, allowMalformed: true)),
  ];
}

/// 单 worker 客户端:spawn + 请求/响应协议。
class _JsonlWorker {
  _JsonlWorker(this.idleTimeout) {
    _init();
  }

  /// 测试用:不 spawn,永远等不到 ready。
  _JsonlWorker.zombie() : idleTimeout = Duration.zero;

  final Duration idleTimeout;

  final _pending = <int, Completer<List<Map<String, dynamic>?>>>{};
  final _responses = ReceivePort();
  final _control = ReceivePort();
  int _nextRequestId = 0;
  SendPort? _requestPort;
  bool _failed = false;
  bool _exited = false;
  StreamSubscription<dynamic>? _responsesSub;
  StreamSubscription<dynamic>? _controlSub;

  bool get isDead => _failed || _exited;

  void _init() {
    Isolate.spawn(
      _jsonlDecodeWorkerEntry,
      _JsonlSpawnArgs(
        control: _control.sendPort,
        responses: _responses.sendPort,
        idleTimeoutMillis: idleTimeout.inMilliseconds,
      ),
      debugName: 'transcript-tail-decoder',
      onError: _control.sendPort,
    ).then(
      (_) {},
      onError: (Object error, StackTrace _) {
        _failed = true;
        _failAllPending(error);
      },
    );
    _responsesSub = _responses.listen(_onResponse);
    _controlSub = _control.listen(_onControl);
  }

  Future<List<Map<String, dynamic>?>> decode(
    List<List<int>> lines, {
    required Duration readyTimeout,
  }) {
    final port = _requestPort;
    if (port == null) {
      if (isDead) {
        throw StateError('transcript-tail-decoder worker dead');
      }
      return _waitReady(readyTimeout).then((readyPort) {
        if (readyPort == null) {
          throw TimeoutException(
            'transcript-tail-decoder worker not ready',
            readyTimeout,
          );
        }
        return _send(readyPort, lines);
      });
    }
    if (isDead) {
      throw StateError('transcript-tail-decoder worker dead');
    }
    return _send(port, lines);
  }

  Future<SendPort?> _waitReady(Duration readyTimeout) async {
    final deadline = DateTime.now().add(readyTimeout);
    while (_requestPort == null && !isDead) {
      if (DateTime.now().isAfter(deadline)) {
        _failed = true;
        _failAllPending(
          TimeoutException(
            'transcript-tail-decoder worker not ready',
            readyTimeout,
          ),
        );
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _requestPort;
  }

  Future<List<Map<String, dynamic>?>> _send(
    SendPort port,
    List<List<int>> lines,
  ) async {
    final requestId = _nextRequestId++;
    final completer = Completer<List<Map<String, dynamic>?>>();
    _pending[requestId] = completer;
    try {
      port.send(_JsonlRequest(requestId: requestId, lines: lines));
    } catch (error) {
      _pending.remove(requestId);
      _failed = true;
      _failAllPending(error);
      throw StateError('transcript-tail-decoder send failed: $error');
    }
    return completer.future;
  }

  void _onControl(Object? message) {
    if (message is SendPort) {
      _requestPort = message;
      return;
    }
    if (message is List && message.length == 2) {
      // Isolate.spawn(onError) → [error, stackTrace]。
      _failed = true;
      _failAllPending(message[0]);
    }
  }

  void _onResponse(Object? message) {
    if (message is _JsonlWorkerExited) {
      _exited = true;
      _failAllPending(
        StateError('transcript-tail-decoder worker exited while pending'),
      );
      return;
    }
    final response = message as _JsonlResponse;
    final completer = _pending.remove(response.requestId);
    completer?.complete(response.result);
  }

  void _failAllPending(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  void close() {
    _exited = true;
    _controlSub?.cancel();
    _responsesSub?.cancel();
    _controlSub = null;
    _responsesSub = null;
    _control.close();
    _responses.close();
    _failAllPending(StateError('transcript-tail-decoder worker closed'));
  }
}

class _JsonlSpawnArgs {
  const _JsonlSpawnArgs({
    required this.control,
    required this.responses,
    required this.idleTimeoutMillis,
  });

  final SendPort control;
  final SendPort responses;
  final int idleTimeoutMillis;
}

class _JsonlRequest {
  const _JsonlRequest({required this.requestId, required this.lines});

  final int requestId;
  final List<List<int>> lines;
}

class _JsonlResponse {
  const _JsonlResponse(this.requestId, this.result);

  final int requestId;
  final List<Map<String, dynamic>?> result;
}

class _JsonlWorkerExited {
  const _JsonlWorkerExited();
}

/// Worker 入口:常驻解码(无状态),空闲超时后退出。
///
/// 空闲计时器只在响应发出后重新武装,避免大 transcript 全量解码期间
/// 被空闲退出打断。
void _jsonlDecodeWorkerEntry(_JsonlSpawnArgs args) {
  final requests = ReceivePort();
  args.control.send(requests.sendPort); // ready

  Timer? idleTimer;
  void armIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(Duration(milliseconds: args.idleTimeoutMillis), () {
      args.responses.send(const _JsonlWorkerExited());
      requests.close();
    });
  }

  armIdleTimer();
  requests.listen((message) {
    if (message is _JsonlRequest) {
      idleTimer?.cancel();
      final out = <Map<String, dynamic>?>[];
      for (final line in message.lines) {
        out.add(_tryDecode(utf8.decode(line, allowMalformed: true)));
      }
      args.responses.send(_JsonlResponse(message.requestId, out));
      armIdleTimer();
    }
  });
}

Map<String, dynamic>? _tryDecode(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// 批解码入口(替代原 `Isolate.run` 实现):行 → 常驻 worker → 解码结果。
/// worker 不可用时回退 [decodeJsonlLinesSync]。
Future<List<Map<String, dynamic>?>> decodeJsonlLines(
  List<List<int>> lines,
) {
  if (lines.isEmpty) return Future.value(const []);
  return JsonlDecodeWorker.instance.decode(lines);
}
