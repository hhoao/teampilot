import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../cli/claude/capabilities/history/compatible_jsonl.dart';
import '../cli/codex/capabilities/history/ai_transcript.dart';
import '../cli/cursor/capabilities/history/ai_transcript.dart';
import 'ai_history_page.dart';
import 'jsonl_decode_worker.dart';
import 'jsonl_transcript_page_parser.dart';

/// Resident worker for decoding and assembling paged JSONL transcript data.
final class JsonlPageWorker {
  JsonlPageWorker._();

  static final JsonlPageWorker instance = JsonlPageWorker._();

  @visibleForTesting
  Duration idleTimeout = const Duration(seconds: 30);

  @visibleForTesting
  Duration readyTimeout = const Duration(seconds: 10);

  @visibleForTesting
  Duration requestTimeout = const Duration(seconds: 30);

  _JsonlPageResidentWorker? _worker;

  Future<AiHistoryPage?> parse({
    required String adapterId,
    required List<JsonlTranscriptLine> lines,
    required int limit,
    required String sourceToken,
    required bool rebuilt,
  }) async {
    if (lines.isEmpty) {
      return _parserFor(adapterId).parse(
        lines: lines,
        limit: limit,
        sourceToken: sourceToken,
        rebuilt: rebuilt,
      );
    }

    final sw = Stopwatch()..start();
    var byteCount = 0;
    for (final line in lines) {
      byteCount += line.bytes.length;
    }
    final worker = _ensureWorker();
    try {
      final page = await worker.parse(
        adapterId: adapterId,
        lines: lines,
        limit: limit,
        sourceToken: sourceToken,
        rebuilt: rebuilt,
        readyTimeout: readyTimeout,
        requestTimeout: requestTimeout,
      );
      sw.stop();
      if (kDebugMode) {
        debugPrint(
          '[ai-history-timing] jsonl-page adapter=$adapterId '
          'lines=${lines.length} bytes=$byteCount ms=${sw.elapsedMilliseconds}',
        );
      }
      return page;
    } catch (_) {
      if (worker.isDead) _discardWorker(worker);
      rethrow;
    }
  }

  @visibleForTesting
  bool get debugHasResidentWorker => _worker != null;

  /// Installs a worker which never announces readiness for timeout tests.
  @visibleForTesting
  void debugInstallZombieWorker() {
    _discardWorker();
    _worker = _JsonlPageResidentWorker.zombie();
  }

  @visibleForTesting
  void dispose() {
    _discardWorker();
  }

  _JsonlPageResidentWorker _ensureWorker() {
    final existing = _worker;
    if (existing != null && !existing.isDead) return existing;
    existing?.close();
    return _worker = _JsonlPageResidentWorker(idleTimeout);
  }

  void _discardWorker([_JsonlPageResidentWorker? expected]) {
    final worker = _worker;
    if (worker == null || (expected != null && !identical(worker, expected))) {
      return;
    }
    _worker = null;
    worker.close();
  }
}

JsonlTranscriptPageParser _parserFor(String adapterId) {
  final append = switch (adapterId) {
    'claude' || 'flashskyai' => appendClaudeJsonlEvent,
    'codex' => appendCodexJsonlEvent,
    'cursor' => appendCursorJsonlEvent,
    _ => throw UnsupportedError(
      'No JSONL page worker adapter for "$adapterId"',
    ),
  };
  return JsonlTranscriptPageParser(
    lineAppend: append,
    fallbackPrefix: adapterId,
  );
}

final class _JsonlPageResidentWorker {
  _JsonlPageResidentWorker(this.idleTimeout) {
    _start();
  }

  _JsonlPageResidentWorker.zombie() : idleTimeout = Duration.zero;

  final Duration idleTimeout;
  final _pending = <int, Completer<AiHistoryPage?>>{};
  final _responses = ReceivePort();
  final _control = ReceivePort();
  final _ready = Completer<SendPort>();
  var _nextRequestId = 0;
  var _failed = false;
  var _closed = false;
  Isolate? _isolate;
  StreamSubscription<dynamic>? _responsesSub;
  StreamSubscription<dynamic>? _controlSub;

  bool get isDead => _failed || _closed;

  void _start() {
    _responsesSub = _responses.listen(_onResponse, onDone: _onResponseClosed);
    _controlSub = _control.listen(_onControl, onDone: _onControlClosed);
    Isolate.spawn(
      _jsonlPageWorkerEntry,
      _JsonlPageSpawnArgs(
        control: _control.sendPort,
        responses: _responses.sendPort,
        idleTimeoutMillis: idleTimeout.inMilliseconds,
      ),
      debugName: 'session-history-page-parser',
      onError: _control.sendPort,
      onExit: _control.sendPort,
    ).then((isolate) {
      if (isDead) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    }, onError: (Object error, StackTrace stack) => _fail(error, stack));
  }

  Future<AiHistoryPage?> parse({
    required String adapterId,
    required List<JsonlTranscriptLine> lines,
    required int limit,
    required String sourceToken,
    required bool rebuilt,
    required Duration readyTimeout,
    required Duration requestTimeout,
  }) async {
    if (isDead) {
      throw StateError('session-history-page worker is unavailable');
    }
    final port = await _ready.future.timeout(
      readyTimeout,
      onTimeout: () {
        final error = TimeoutException(
          'session-history-page worker did not become ready',
          readyTimeout,
        );
        _fail(error, StackTrace.current);
        throw error;
      },
    );
    if (isDead) throw StateError('session-history-page worker is unavailable');

    final requestId = _nextRequestId++;
    final completer = Completer<AiHistoryPage?>();
    _pending[requestId] = completer;
    try {
      port.send(
        _JsonlPageRequest(
          requestId: requestId,
          adapterId: adapterId,
          lines: [
            for (final line in lines)
              _JsonlPageLineTransfer(
                offset: line.offset,
                bytes: TransferableTypedData.fromList([
                  Uint8List.fromList(line.bytes),
                ]),
              ),
          ],
          limit: limit,
          sourceToken: sourceToken,
          rebuilt: rebuilt,
        ),
      );
    } catch (error, stack) {
      _pending.remove(requestId);
      _fail(error, stack);
      rethrow;
    }
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        final error = TimeoutException(
          'session-history-page worker request timed out',
          requestTimeout,
        );
        _fail(error, StackTrace.current);
        throw error;
      },
    );
  }

  void _onControl(Object? message) {
    if (message is SendPort) {
      if (!isDead && !_ready.isCompleted) _ready.complete(message);
      return;
    }
    if (message is List && message.length == 2) {
      _fail(message[0], StackTrace.fromString('${message[1]}'));
      return;
    }
    if (message == null) {
      _fail(
        StateError('session-history-page worker exited'),
        StackTrace.current,
      );
    }
  }

  void _onResponse(Object? message) {
    switch (message) {
      case _JsonlPageResponse(:final requestId, :final page):
        final completer = _pending.remove(requestId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(page);
        }
      case _JsonlPageFailure(:final requestId, :final error, :final stack):
        final completer = _pending.remove(requestId);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error, stack);
        }
      case _JsonlPageWorkerExited():
        _fail(
          StateError('session-history-page worker exited while pending'),
          StackTrace.current,
        );
      default:
        _fail(
          StateError('session-history-page worker received invalid response'),
          StackTrace.current,
        );
    }
  }

  void _onResponseClosed() => _fail(
    StateError('session-history-page response port closed'),
    StackTrace.current,
  );

  void _onControlClosed() => _fail(
    StateError('session-history-page control port closed'),
    StackTrace.current,
  );

  void _fail(Object error, StackTrace stack) {
    if (_failed) return;
    _failed = true;
    if (!_ready.isCompleted) _ready.completeError(error, stack);
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fail(
      StateError('session-history-page worker disposed'),
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

final class _JsonlPageLineTransfer {
  const _JsonlPageLineTransfer({required this.offset, required this.bytes});

  final int offset;
  final TransferableTypedData bytes;

  JsonlTranscriptLine materialize(Map<String, dynamic>? event) =>
      JsonlTranscriptLine(
        offset: offset,
        bytes: bytes.materialize().asUint8List(),
        decodedEvent: event,
      );
}

final class _JsonlPageSpawnArgs {
  const _JsonlPageSpawnArgs({
    required this.control,
    required this.responses,
    required this.idleTimeoutMillis,
  });

  final SendPort control;
  final SendPort responses;
  final int idleTimeoutMillis;
}

final class _JsonlPageRequest {
  const _JsonlPageRequest({
    required this.requestId,
    required this.adapterId,
    required this.lines,
    required this.limit,
    required this.sourceToken,
    required this.rebuilt,
  });

  final int requestId;
  final String adapterId;
  final List<_JsonlPageLineTransfer> lines;
  final int limit;
  final String sourceToken;
  final bool rebuilt;
}

final class _JsonlPageResponse {
  const _JsonlPageResponse(this.requestId, this.page);

  final int requestId;
  final AiHistoryPage? page;
}

final class _JsonlPageFailure {
  const _JsonlPageFailure(this.requestId, this.error, this.stack);

  final int requestId;
  final Object error;
  final StackTrace stack;
}

final class _JsonlPageWorkerExited {
  const _JsonlPageWorkerExited();
}

void _jsonlPageWorkerEntry(_JsonlPageSpawnArgs args) {
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
    args.responses.send(const _JsonlPageWorkerExited());
  }

  void armIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(Duration(milliseconds: args.idleTimeoutMillis), exit);
  }

  armIdleTimer();
  requests.listen((message) async {
    if (message is! _JsonlPageRequest || exited) return;
    idleTimer?.cancel();
    activeRequests++;
    try {
      final rawLines = [
        for (final line in message.lines) line.materialize(null),
      ];
      final events = decodeJsonlLinesSync([
        for (final line in rawLines) line.bytes,
      ]);
      final lines = [
        for (var i = 0; i < rawLines.length; i++)
          JsonlTranscriptLine(
            offset: rawLines[i].offset,
            bytes: rawLines[i].bytes,
            decodedEvent: events[i],
          ),
      ];
      final page = _parserFor(message.adapterId).parse(
        lines: lines,
        limit: message.limit,
        sourceToken: message.sourceToken,
        rebuilt: message.rebuilt,
      );
      args.responses.send(_JsonlPageResponse(message.requestId, page));
    } catch (error, stack) {
      args.responses.send(_JsonlPageFailure(message.requestId, error, stack));
    } finally {
      activeRequests--;
      if (activeRequests == 0 && !exited) armIdleTimer();
    }
  });
}
