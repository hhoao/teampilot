import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:meta/meta.dart';

/// JSONL 批解码的常驻 worker(全局共享一个实例)。
///
/// 替代每轮 live refresh 一次 `Isolate.run`(spawn + 销毁):JSONL CLI
/// (Claude/Codex/Cursor/FlashskyAI)的 tail 增量刷新每轮都解码新行,
/// 高频场景下消除每次 spawn 成本。worker 无状态(只做解码),
/// 空闲 [idleTimeout] 后退出,下次调用按需重拉。
class JsonlDecodeWorker {
  JsonlDecodeWorker._();

  static final JsonlDecodeWorker instance = JsonlDecodeWorker._();

  /// worker 空闲时长(测试可缩短以验证空闲回收)。
  Duration idleTimeout = const Duration(seconds: 30);

  _JsonlWorker? _worker;

  Future<List<Map<String, dynamic>?>> decode(List<List<int>> lines) async {
    var worker = _worker;
    if (worker == null || worker.isDead) {
      worker = _JsonlWorker(idleTimeout);
      _worker = worker;
    }
    return worker.decode(lines);
  }

  @visibleForTesting
  void dispose() {
    _worker?.close();
    _worker = null;
  }
}

/// 单 worker 客户端:spawn + 请求/响应协议。
class _JsonlWorker {
  _JsonlWorker(this.idleTimeout) {
    _init();
  }

  final Duration idleTimeout;

  final _pending = <int, Completer<List<Map<String, dynamic>?>>>{};
  final _responses = ReceivePort();
  final _control = ReceivePort();
  int _nextRequestId = 0;
  SendPort? _requestPort;
  bool _failed = false;
  bool _exited = false;

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
    );
    _responses.listen(_onResponse);
    _control.listen(_onControl);
  }

  Future<List<Map<String, dynamic>?>> decode(List<List<int>> lines) {
    final port = _requestPort;
    if (port == null) {
      if (isDead) {
        throw StateError('transcript-tail-decoder worker dead');
      }
      return _waitReady().then(
        (readyPort) =>
            readyPort == null ? const [] : _send(readyPort, lines),
      );
    }
    return _send(port, lines);
  }

  Future<SendPort?> _waitReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_requestPort == null && !isDead) {
      if (DateTime.now().isAfter(deadline)) {
        _failAllPending(
          TimeoutException('transcript-tail-decoder worker not ready'),
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
    port.send(_JsonlRequest(requestId: requestId, lines: lines));
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
      completer.completeError(error);
    }
  }

  void close() {
    _exited = true;
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
      armIdleTimer();
      final out = <Map<String, dynamic>?>[];
      for (final line in message.lines) {
        out.add(_tryDecode(utf8.decode(line, allowMalformed: true)));
      }
      args.responses.send(_JsonlResponse(message.requestId, out));
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
/// 行与结果均跨 isolate 传输(纯数据,可发送)。
Future<List<Map<String, dynamic>?>> decodeJsonlLines(
  List<List<int>> lines,
) {
  if (lines.isEmpty) return Future.value(const []);
  return JsonlDecodeWorker.instance.decode(lines);
}
