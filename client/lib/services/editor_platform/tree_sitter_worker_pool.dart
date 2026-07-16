import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:teampilot_tree_sitter/teampilot_tree_sitter.dart';

import '../../utils/logging/logger.dart';
import 'worker_protocol.dart';

/// Production [TsWorkerPool] backed by up to [maxIsolates] worker isolates
/// (default 2). Each session is pinned to one worker for its lifetime; the pool
/// spreads sessions across workers by least-loaded assignment.
///
/// Unit tests use a fake pool instead — this class requires the
/// `teampilot_tree_sitter` native asset, which is not built for the plain
/// `flutter test` host.
class TreeSitterWorkerPool implements TsWorkerPool {
  TreeSitterWorkerPool({this.maxIsolates = 2})
    : assert(maxIsolates >= 1, 'need at least one worker isolate');

  final int maxIsolates;
  final List<_WorkerIsolate> _workers = [];
  bool _disposed = false;

  @override
  TsSessionHandle openSession(String sessionId) {
    if (_disposed) {
      throw StateError('TreeSitterWorkerPool has been disposed');
    }
    final worker = _pickWorker();
    return worker.attach(sessionId);
  }

  _WorkerIsolate _pickWorker() {
    // Grow the pool until the cap while every existing worker is already busy;
    // otherwise reuse the least-loaded worker (session affinity keeps a session
    // on that worker for its lifetime).
    final allBusy = _workers.every((w) => w.sessionCount > 0);
    if (_workers.length < maxIsolates && (_workers.isEmpty || allBusy)) {
      final worker = _WorkerIsolate()..start();
      _workers.add(worker);
      return worker;
    }
    _workers.sort((a, b) => a.sessionCount.compareTo(b.sessionCount));
    return _workers.first;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final worker in _workers) {
      worker.shutdown();
    }
    _workers.clear();
  }
}

/// One worker isolate plus the routing state the pool needs to fan query
/// replies back to the correct session channel.
class _WorkerIsolate {
  final ReceivePort _fromWorker = ReceivePort();
  final List<TsCommand> _pending = [];
  final Map<String, StreamController<TsQueryResult>> _controllers = {};

  Isolate? _isolate;
  SendPort? _toWorker;
  int sessionCount = 0;

  /// Set by [shutdown] when it runs while [Isolate.spawn] is still in
  /// flight, so the `then` callback below kills the isolate the moment it
  /// spawns instead of leaking a running isolate the pool no longer tracks.
  bool _shutdownRequested = false;

  void start() {
    _fromWorker.listen(_onMessage);
    Isolate.spawn(_workerEntry, _fromWorker.sendPort).then(
      (isolate) {
        if (_shutdownRequested) {
          isolate.kill(priority: Isolate.immediate);
          return;
        }
        _isolate = isolate;
      },
      onError: (Object error, StackTrace stackTrace) {
        appLogger.e(
          'TreeSitterWorkerPool: worker isolate spawn failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _toWorker = message;
      for (final command in _pending) {
        message.send(command);
      }
      _pending.clear();
      return;
    }
    if (message is TsQueryResult) {
      _controllers[message.sessionId]?.add(message);
    }
  }

  TsSessionHandle attach(String sessionId) {
    final controller = StreamController<TsQueryResult>.broadcast();
    _controllers[sessionId] = controller;
    sessionCount++;
    return _PooledSessionHandle(sessionId, this, controller);
  }

  void send(TsCommand command) {
    final port = _toWorker;
    if (port == null) {
      _pending.add(command);
    } else {
      port.send(command);
    }
  }

  void detach(String sessionId) {
    final controller = _controllers.remove(sessionId);
    if (controller != null) {
      sessionCount--;
      unawaited(controller.close());
    }
  }

  void shutdown() {
    _shutdownRequested = true;
    for (final controller in _controllers.values) {
      unawaited(controller.close());
    }
    _controllers.clear();
    _fromWorker.close();
    // If spawn hasn't resolved yet, the `then` callback in start() checks
    // `_shutdownRequested` and kills it there instead — no isolate leaks
    // even when shutdown races the spawn.
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

class _PooledSessionHandle implements TsSessionHandle {
  _PooledSessionHandle(this._sessionId, this._worker, this._controller);

  final String _sessionId;
  final _WorkerIsolate _worker;
  final StreamController<TsQueryResult> _controller;
  bool _closed = false;

  @override
  Stream<TsQueryResult> get results => _controller.stream;

  @override
  void send(TsCommand command) {
    if (_closed) return;
    _worker.send(command);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _worker.detach(_sessionId);
  }
}

// --------------------------------------------------------------------------
// Worker isolate side
// --------------------------------------------------------------------------

/// Entry point running inside each worker isolate. Owns one parse tree per
/// session and processes commands serially in arrival order.
void _workerEntry(SendPort toMain) {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);
  final sessions = <String, _WorkerSessionState>{};

  fromMain.listen((message) {
    final command = message as TsCommand;
    switch (command) {
      case TsOpen():
        sessions.remove(command.sessionId)?.dispose();
        sessions[command.sessionId] = _WorkerSessionState.open(command);
      case TsEdit():
        sessions[command.sessionId]?.applyEdit(command);
      case TsQueryRange():
        final result = sessions[command.sessionId]?.runQuery(command);
        if (result != null) {
          toMain.send(result);
        }
      case TsDispose():
        sessions.remove(command.sessionId)?.dispose();
    }
  });
}

/// Per-session native state living entirely inside a worker isolate.
class _WorkerSessionState {
  _WorkerSessionState._({
    required this.sessionId,
    required this.parser,
    required this.tree,
    required this.query,
    required this.bytes,
    required this.editSeq,
  });

  factory _WorkerSessionState.open(TsOpen command) {
    final language = _languageFor(command.grammarId);
    if (language == null) {
      // Unknown grammar → keep an empty session so queries reply with no
      // captures rather than the UI hanging on a missing session.
      return _WorkerSessionState._(
        sessionId: command.sessionId,
        parser: null,
        tree: null,
        query: null,
        bytes: command.utf8Bytes,
        editSeq: command.seq,
      );
    }
    final parser = TsParser()..setLanguage(language);
    final tree = parser.parseUtf8(command.utf8Bytes);
    final query = command.highlightsQuery.isEmpty
        ? null
        : TsQuery(language, command.highlightsQuery);
    return _WorkerSessionState._(
      sessionId: command.sessionId,
      parser: parser,
      tree: tree,
      query: query,
      bytes: command.utf8Bytes,
      editSeq: command.seq,
    );
  }

  final String sessionId;
  final TsParser? parser;
  TsTree? tree;
  final TsQuery? query;
  Uint8List bytes;
  int editSeq;

  void applyEdit(TsEdit command) {
    editSeq = command.seq;
    final oldBytes = bytes;
    final newBytes = command.utf8Bytes;
    bytes = newBytes;
    final parser = this.parser;
    final oldTree = tree;
    if (parser == null || oldTree == null) return;
    parser.edit(
      oldTree,
      TsInputEdit(
        startByte: command.startByte,
        oldEndByte: command.oldEndByte,
        newEndByte: command.newEndByte,
        startPoint: _pointForByte(oldBytes, command.startByte),
        oldEndPoint: _pointForByte(oldBytes, command.oldEndByte),
        newEndPoint: _pointForByte(newBytes, command.newEndByte),
      ),
    );
    tree = parser.parseUtf8(newBytes, oldTree: oldTree);
    oldTree.dispose();
  }

  TsQueryResult runQuery(TsQueryRange command) {
    final tree = this.tree;
    final query = this.query;
    final captures = <TsByteCapture>[];
    if (tree != null && query != null) {
      final endByte = command.endByte > bytes.length
          ? bytes.length
          : command.endByte;
      final startByte = command.startByte < 0 ? 0 : command.startByte;
      for (final capture in query.captures(
        tree,
        startByte: startByte,
        endByte: endByte,
      )) {
        captures.add(
          TsByteCapture(
            name: capture.name,
            startByte: capture.startByte,
            endByte: capture.endByte,
          ),
        );
      }
    }
    return TsQueryResult(
      sessionId: sessionId,
      requestId: command.requestId,
      editSeq: editSeq,
      startByte: command.startByte,
      endByte: command.endByte,
      captures: captures,
    );
  }

  void dispose() {
    tree?.dispose();
    tree = null;
    query?.dispose();
    parser?.dispose();
  }
}

TsLanguage? _languageFor(String grammarId) {
  switch (grammarId) {
    case 'json':
      return TsLanguage.json();
    case 'dart':
      return TsLanguage.dart();
    case 'yaml':
      return TsLanguage.yaml();
    case 'markdown':
      return TsLanguage.markdown();
    case 'python':
      return TsLanguage.python();
    case 'rust':
      return TsLanguage.rust();
    case 'typescript':
      return TsLanguage.typescript();
    case 'bash':
      return TsLanguage.bash();
    case 'xml':
      return TsLanguage.xml();
    case 'toml':
      return TsLanguage.toml();
    case 'css':
      return TsLanguage.css();
    default:
      return null;
  }
}

/// Computes the zero-based (row, column-in-bytes) position of [byteOffset]
/// within [bytes] for tree-sitter's incremental edit points.
TsPoint _pointForByte(Uint8List bytes, int byteOffset) {
  final limit = byteOffset > bytes.length ? bytes.length : byteOffset;
  var row = 0;
  var lineStartByte = 0;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 0x0A) {
      row++;
      lineStartByte = i + 1;
    }
  }
  return TsPoint(row, limit - lineStartByte);
}
