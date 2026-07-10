import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot/services/editor_platform/worker_protocol.dart';

/// In-process [TsWorkerPool] test double.
///
/// It does **not** run tree-sitter. Instead it applies a canned rule: every
/// double-quoted run in the (assumed ASCII) source becomes a `string` capture.
/// That is enough to exercise `DocumentSession`'s cache, viewport-first, edit
/// invalidation, and stale-drop logic without native assets.
///
/// Reply timing is controllable:
/// * [autoRespond] `true` (default) delivers each query reply after
///   [replyDelay] (default `Duration.zero`, i.e. next event-loop turn), so
///   awaited viewport queries resolve within the frame budget.
/// * [autoRespond] `false` queues replies until [deliverPending] is called, for
///   deterministic stale-drop / timeout tests.
class FakeTsWorkerPool implements TsWorkerPool {
  FakeTsWorkerPool({this.autoRespond = true, this.replyDelay = Duration.zero});

  final bool autoRespond;
  final Duration replyDelay;

  final List<FakeTsSessionHandle> handles = [];

  /// Total queries received across all sessions (for assertions on how much
  /// work the session enqueued).
  int queryCount = 0;

  @override
  TsSessionHandle openSession(String sessionId) {
    final handle = FakeTsSessionHandle(this, sessionId);
    handles.add(handle);
    return handle;
  }

  /// Flushes every queued reply (only meaningful when [autoRespond] is false).
  void deliverPending() {
    for (final handle in handles) {
      handle.deliverPending();
    }
  }

  @override
  Future<void> dispose() async {
    for (final handle in handles) {
      handle.close();
    }
    handles.clear();
  }
}

class FakeTsSessionHandle implements TsSessionHandle {
  FakeTsSessionHandle(this._pool, this.sessionId);

  final FakeTsWorkerPool _pool;
  final String sessionId;
  final StreamController<TsQueryResult> _controller =
      StreamController<TsQueryResult>.broadcast();
  final List<TsQueryResult> _queued = [];

  Uint8List _bytes = Uint8List(0);
  int _editSeq = 0;
  bool _closed = false;

  @override
  Stream<TsQueryResult> get results => _controller.stream;

  @override
  void send(TsCommand command) {
    if (_closed) return;
    switch (command) {
      case TsOpen():
        _bytes = command.utf8Bytes;
        _editSeq = command.seq;
      case TsEdit():
        _bytes = command.utf8Bytes;
        _editSeq = command.seq;
      case TsQueryRange():
        _pool.queryCount++;
        final result = _buildResult(command);
        if (_pool.autoRespond) {
          Future<void>.delayed(_pool.replyDelay, () {
            if (!_closed) _controller.add(result);
          });
        } else {
          _queued.add(result);
        }
      case TsDispose():
        break;
    }
  }

  void deliverPending() {
    if (_closed) return;
    final pending = List<TsQueryResult>.from(_queued);
    _queued.clear();
    for (final result in pending) {
      _controller.add(result);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_controller.close());
  }

  TsQueryResult _buildResult(TsQueryRange command) {
    final text = utf8.decode(_bytes, allowMalformed: true);
    final captures = <TsByteCapture>[];
    // ASCII assumption: string index == byte offset for canned test data.
    final matches = RegExp(r'"(?:[^"\\]|\\.)*"').allMatches(text);
    for (final match in matches) {
      final start = match.start;
      final end = match.end;
      if (start < command.endByte && end > command.startByte) {
        captures.add(
          TsByteCapture(name: 'string', startByte: start, endByte: end),
        );
      }
    }
    return TsQueryResult(
      sessionId: sessionId,
      requestId: command.requestId,
      editSeq: _editSeq,
      startByte: command.startByte,
      endByte: command.endByte,
      captures: captures,
    );
  }
}
