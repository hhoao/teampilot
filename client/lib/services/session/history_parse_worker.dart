import 'dart:async';
import 'dart:isolate';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';

import 'history_parse_worker_adapters.dart';

/// Result returned by a worker-safe transcript parse and optional enrichment.
final class HistoryParseResult {
  const HistoryParseResult({
    required this.messages,
    this.indexSnapshot,
    this.parseTime = Duration.zero,
    this.enrichTime = Duration.zero,
  });

  final List<AiMessage> messages;
  final Object? indexSnapshot;
  final Duration parseTime;
  final Duration enrichTime;
}

/// Boundary for transcript parsing performed away from the caller isolate.
abstract interface class HistoryParseExecutor {
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  });

  Future<void> dispose();
}

/// A lazily spawned transcript parser retained until it becomes idle.
///
/// Worker failures are deliberately returned to the caller. Parsing on the
/// caller isolate would reintroduce the UI stalls this worker prevents.
final class HistoryParseWorker implements HistoryParseExecutor {
  HistoryParseWorker({
    @visibleForTesting this.idleTimeout = const Duration(seconds: 30),
    @visibleForTesting this.readyTimeout = const Duration(seconds: 10),
    @visibleForTesting this.requestTimeout = const Duration(seconds: 30),
    @visibleForTesting this.queueTimeout = const Duration(minutes: 5),
    @visibleForTesting
    this.debugBehavior = HistoryParseWorkerDebugBehavior.normal,
  });

  static final HistoryParseWorker instance = HistoryParseWorker();

  @visibleForTesting
  final Duration idleTimeout;

  @visibleForTesting
  final Duration readyTimeout;

  @visibleForTesting
  final Duration requestTimeout;

  @visibleForTesting
  final Duration queueTimeout;

  @visibleForTesting
  final HistoryParseWorkerDebugBehavior debugBehavior;

  _HistoryParseResidentWorker? _worker;
  var _spawnCount = 0;

  @visibleForTesting
  int get debugSpawnCount => _spawnCount;

  @visibleForTesting
  bool get debugHasResidentWorker => _worker != null;

  @override
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  }) async {
    final worker = _ensureWorker();
    try {
      return await worker.parse(
        adapterId: adapterId,
        bundle: bundle,
        workerEnricherId: workerEnricherId,
        sourceToken: sourceToken,
        rootTranscriptPath: rootTranscriptPath,
        readyTimeout: readyTimeout,
        requestTimeout: requestTimeout,
        queueTimeout: queueTimeout,
      );
    } catch (_) {
      if (worker.isDead) {
        _discardWorker(worker);
      }
      rethrow;
    }
  }

  _HistoryParseResidentWorker _ensureWorker() {
    final existing = _worker;
    if (existing != null && !existing.isDead) return existing;

    _spawnCount += 1;
    late final _HistoryParseResidentWorker worker;
    worker = _HistoryParseResidentWorker(
      idleTimeout,
      debugBehavior: debugBehavior,
      onTerminal: () => _discardWorker(worker),
    );
    return _worker = worker;
  }

  void _discardWorker([_HistoryParseResidentWorker? expected]) {
    final worker = _worker;
    if (worker == null || (expected != null && !identical(worker, expected))) {
      return;
    }
    _worker = null;
    worker.close();
  }

  /// Installs a worker which never announces readiness.
  @visibleForTesting
  void debugInstallZombieWorker() {
    _discardWorker();
    late final _HistoryParseResidentWorker worker;
    worker = _HistoryParseResidentWorker.zombie(
      onTerminal: () => _discardWorker(worker),
    );
    _worker = worker;
  }

  @visibleForTesting
  Future<void> debugWaitForPendingRequest() {
    final worker = _worker;
    if (worker == null) {
      throw StateError('session-history-parser worker is unavailable');
    }
    return worker.debugWaitForPendingRequest();
  }

  @visibleForTesting
  Future<void> debugTriggerIsolateError() =>
      _debugTrigger(_HistoryParseDebugCommandKind.isolateError);

  @visibleForTesting
  Future<void> debugTriggerIsolateExit() =>
      _debugTrigger(_HistoryParseDebugCommandKind.exit);

  Future<void> _debugTrigger(_HistoryParseDebugCommandKind kind) {
    final worker = _worker;
    if (worker == null) {
      throw StateError('session-history-parser worker is unavailable');
    }
    return worker.debugTrigger(kind, readyTimeout);
  }

  @visibleForTesting
  void debugCloseResponsePort() {
    _worker?.debugCloseResponsePort();
  }

  @override
  Future<void> dispose() async {
    _discardWorker();
  }
}

@visibleForTesting
enum HistoryParseWorkerDebugBehavior {
  normal,
  stallRequests,
  delayFirstResponse,
}

final class _HistoryParseResidentWorker {
  _HistoryParseResidentWorker(
    this.idleTimeout, {
    required this.debugBehavior,
    required this.onTerminal,
  }) {
    _start();
  }

  _HistoryParseResidentWorker.zombie({required this.onTerminal})
    : idleTimeout = Duration.zero,
      debugBehavior = HistoryParseWorkerDebugBehavior.normal;

  final Duration idleTimeout;
  final HistoryParseWorkerDebugBehavior debugBehavior;
  final void Function() onTerminal;
  final _pending = <int, Completer<HistoryParseResult>>{};
  final _responses = ReceivePort();
  final _control = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pendingRequest = Completer<void>();

  Isolate? _isolate;
  StreamSubscription<dynamic>? _responsesSub;
  StreamSubscription<dynamic>? _controlSub;
  var _nextRequestId = 0;
  Future<void> _requestTail = Future<void>.value();
  var _failed = false;
  var _closed = false;

  bool get isDead => _failed || _closed;

  void _start() {
    _responsesSub = _responses.listen(_onResponse, onDone: _onResponseClosed);
    _controlSub = _control.listen(_onControl, onDone: _onControlClosed);
    Isolate.spawn(
      _historyParseWorkerEntry,
      _HistoryParseSpawnArgs(
        control: _control.sendPort,
        responses: _responses.sendPort,
        idleTimeoutMillis: idleTimeout.inMilliseconds,
        debugBehavior: debugBehavior,
      ),
      debugName: 'session-history-parser',
      onError: _control.sendPort,
      onExit: _control.sendPort,
    ).then(
      (isolate) {
        if (isDead) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _fail(error, stackTrace);
      },
    );
  }

  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    required String? workerEnricherId,
    required String? sourceToken,
    required String? rootTranscriptPath,
    required Duration readyTimeout,
    required Duration requestTimeout,
    required Duration queueTimeout,
  }) async {
    if (isDead) {
      throw StateError('session-history-parser worker is unavailable');
    }

    final port = await _waitReady(readyTimeout);
    if (isDead) {
      throw StateError('session-history-parser worker is unavailable');
    }

    final previous = _requestTail;
    final turn = Completer<void>();
    _requestTail = previous.catchError((_) {}).then((_) => turn.future);

    try {
      await previous.timeout(
        queueTimeout,
        onTimeout: () {
          final error = TimeoutException(
            'session-history-parser worker queue timed out',
            queueTimeout,
          );
          _fail(error, StackTrace.current);
          throw error;
        },
      );
      if (isDead) {
        throw StateError('session-history-parser worker is unavailable');
      }

      final requestId = _nextRequestId++;
      final completer = Completer<HistoryParseResult>();
      _pending[requestId] = completer;
      if (!_pendingRequest.isCompleted) {
        _pendingRequest.complete();
      }
      try {
        port.send(
          _HistoryParseRequest(
            requestId: requestId,
            adapterId: adapterId,
            bundle: bundle,
            workerEnricherId: workerEnricherId,
            sourceToken: sourceToken,
            rootTranscriptPath: rootTranscriptPath,
          ),
        );
      } catch (error, stackTrace) {
        _pending.remove(requestId);
        _fail(error, stackTrace);
        rethrow;
      }

      return await completer.future.timeout(
        requestTimeout,
        onTimeout: () {
          final error = TimeoutException(
            'session-history-parser worker request timed out',
            requestTimeout,
          );
          _fail(error, StackTrace.current);
          throw error;
        },
      );
    } finally {
      if (!turn.isCompleted) {
        turn.complete();
      }
    }
  }

  Future<SendPort> _waitReady(Duration timeout) {
    return _ready.future.timeout(
      timeout,
      onTimeout: () {
        final error = TimeoutException(
          'session-history-parser worker did not become ready',
          timeout,
        );
        _fail(error, StackTrace.current);
        throw error;
      },
    );
  }

  Future<void> debugWaitForPendingRequest() {
    if (_pending.isNotEmpty) return Future.value();
    return _pendingRequest.future;
  }

  Future<void> debugTrigger(
    _HistoryParseDebugCommandKind kind,
    Duration timeout,
  ) async {
    final port = await _waitReady(timeout);
    port.send(_HistoryParseDebugCommand(kind));
  }

  void debugCloseResponsePort() {
    _responses.close();
  }

  void _onControl(Object? message) {
    if (message is SendPort) {
      if (!isDead && !_ready.isCompleted) {
        _ready.complete(message);
      }
      return;
    }
    if (message is List && message.length == 2) {
      _fail(message[0], StackTrace.fromString('${message[1]}'));
      return;
    }
    if (message == null) {
      _fail(
        StateError('session-history-parser worker exited'),
        StackTrace.current,
      );
    }
  }

  void _onResponse(Object? message) {
    switch (message) {
      case _HistoryParseResponse(:final requestId, :final result):
        final completer = _pending.remove(requestId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(result);
        }
      case _HistoryParseFailure(:final requestId, :final error, :final stack):
        final completer = _pending.remove(requestId);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error, stack);
        }
      case _HistoryParseWorkerExited():
        _fail(
          StateError('session-history-parser worker exited while pending'),
          StackTrace.current,
        );
      default:
        _fail(
          StateError('session-history-parser received an invalid response'),
          StackTrace.current,
        );
    }
  }

  void _onResponseClosed() {
    _fail(
      StateError('session-history-parser response port closed'),
      StackTrace.current,
    );
  }

  void _onControlClosed() {
    _fail(
      StateError('session-history-parser control port closed'),
      StackTrace.current,
    );
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_failed) return;
    _failed = true;
    onTerminal();
    if (!_ready.isCompleted) {
      _ready.completeError(error, stackTrace);
    }
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fail(
      StateError('session-history-parser worker disposed'),
      StackTrace.current,
    );
    _responsesSub?.cancel();
    _controlSub?.cancel();
    _responsesSub = null;
    _controlSub = null;
    _responses.close();
    _control.close();
  }
}

final class _HistoryParseSpawnArgs {
  const _HistoryParseSpawnArgs({
    required this.control,
    required this.responses,
    required this.idleTimeoutMillis,
    required this.debugBehavior,
  });

  final SendPort control;
  final SendPort responses;
  final int idleTimeoutMillis;
  final HistoryParseWorkerDebugBehavior debugBehavior;
}

final class _HistoryParseRequest {
  const _HistoryParseRequest({
    required this.requestId,
    required this.adapterId,
    required this.bundle,
    this.workerEnricherId,
    this.sourceToken,
    this.rootTranscriptPath,
  });

  final int requestId;
  final String adapterId;
  final AiTranscriptBundle bundle;
  final String? workerEnricherId;
  final String? sourceToken;
  final String? rootTranscriptPath;
}

final class _HistoryParseResponse {
  const _HistoryParseResponse(this.requestId, this.result);

  final int requestId;
  final HistoryParseResult result;
}

final class _HistoryParseFailure {
  const _HistoryParseFailure(this.requestId, this.error, this.stack);

  final int requestId;
  final Object error;
  final StackTrace stack;
}

final class _HistoryParseWorkerExited {
  const _HistoryParseWorkerExited();
}

enum _HistoryParseDebugCommandKind { isolateError, exit }

final class _HistoryParseDebugCommand {
  const _HistoryParseDebugCommand(this.kind);

  final _HistoryParseDebugCommandKind kind;
}

void _historyParseWorkerEntry(_HistoryParseSpawnArgs args) {
  final requests = ReceivePort();
  args.control.send(requests.sendPort);

  Timer? idleTimer;
  var activeRequests = 0;
  var exited = false;

  void exit() {
    if (exited) return;
    exited = true;
    idleTimer?.cancel();
    requests.close();
    args.responses.send(const _HistoryParseWorkerExited());
  }

  void armIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(Duration(milliseconds: args.idleTimeoutMillis), exit);
  }

  armIdleTimer();
  requests.listen((message) async {
    if (message case _HistoryParseDebugCommand(:final kind)) {
      switch (kind) {
        case _HistoryParseDebugCommandKind.isolateError:
          throw StateError('debug session-history-parser isolate error');
        case _HistoryParseDebugCommandKind.exit:
          exit();
      }
      return;
    }
    if (message is! _HistoryParseRequest || exited) return;
    idleTimer?.cancel();
    activeRequests += 1;
    if (args.debugBehavior == HistoryParseWorkerDebugBehavior.stallRequests) {
      return;
    }
    try {
      if (args.debugBehavior ==
              HistoryParseWorkerDebugBehavior.delayFirstResponse &&
          message.requestId == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      final result = await parseHistoryBundleInWorker(
        adapterId: message.adapterId,
        bundle: message.bundle,
        workerEnricherId: message.workerEnricherId,
        sourceToken: message.sourceToken,
        rootTranscriptPath: message.rootTranscriptPath,
      );
      args.responses.send(_HistoryParseResponse(message.requestId, result));
    } catch (error, stackTrace) {
      args.responses.send(
        _HistoryParseFailure(message.requestId, error, stackTrace),
      );
    } finally {
      activeRequests -= 1;
      if (activeRequests == 0 && !exited) {
        armIdleTimer();
      }
    }
  });
}
