/// Background-isolate wrappers around the FFI engines.
///
/// Both engines call into Rust synchronously through FFI, so running them on
/// the main isolate means either blocking it (native calls cannot be
/// interrupted) or starving frames through microtask chains. These wrappers
/// move the calls onto a worker isolate and talk to it over ports, leaving the
/// UI isolate free to build frames.
///
/// Cancellation is cooperative: the worker checks for a cancel message at each
/// event-loop turn (the search stream yields to the event queue per chunk), so
/// it unwinds, frees its native handle in `finally`, and exits on its own. The
/// worker is never killed from the outside — killing it would leak the native
/// handle and its walker thread.
library;

import 'dart:async';
import 'dart:isolate';

import '../teampilot_search.dart';
import 'file_index.dart';

// ---------------------------------------------------------------------------
// Content search
// ---------------------------------------------------------------------------

/// Matches are forwarded in batches to amortise port message overhead.
const int _kSearchBatchSize = 64;

const String _kCancelMessage = 'cancel';

class _SearchWorkerStart {
  const _SearchWorkerStart({
    required this.reply,
    required this.root,
    required this.options,
  });

  final SendPort reply;
  final String root;
  final TpSearchOptions options;
}

class _SearchWorkerReady {
  const _SearchWorkerReady(this.control);

  final SendPort control;
}

class _SearchWorkerBatch {
  const _SearchWorkerBatch(this.matches);

  final List<TpSearchMatch> matches;
}

class _SearchWorkerFailed {
  const _SearchWorkerFailed(this.message);

  final String message;
}

class _SearchWorkerDone {
  const _SearchWorkerDone();
}

Future<void> _searchWorkerMain(_SearchWorkerStart start) async {
  final control = ReceivePort();
  start.reply.send(_SearchWorkerReady(control.sendPort));
  var cancelled = false;
  final controlSubscription = control.listen((message) {
    if (message == _kCancelMessage) cancelled = true;
  });

  final engine = TpSearchEngine();
  final batch = <TpSearchMatch>[];
  void flush() {
    if (batch.isEmpty) return;
    start.reply.send(_SearchWorkerBatch(List<TpSearchMatch>.of(batch)));
    batch.clear();
  }

  try {
    await for (final match in engine.search(start.root, start.options)) {
      if (cancelled) break;
      batch.add(match);
      if (batch.length >= _kSearchBatchSize) flush();
    }
    if (!cancelled) {
      flush();
      start.reply.send(const _SearchWorkerDone());
    }
  } on Object catch (error) {
    if (!cancelled) start.reply.send(_SearchWorkerFailed('$error'));
  } finally {
    // Belt and braces: makes the Rust walker stop even if the generator is not
    // resumed again, and frees the handle through its own `finally`.
    engine.cancel();
    await controlSubscription.cancel();
    control.close();
  }
}

/// Runs [TpSearchEngine.search] on a worker isolate.
///
/// One instance per search: the Rust engine owns a single FFI handle slot and
/// the worker exits when the walk ends. Each [run] gets its own [ReceivePort]
/// and cancel state, so a cancelled stream never affects a later one.
class IsolatedContentSearch {
  _ContentSearchRun? _run;

  /// Starts [root] search and streams its matches. Call [cancel] or cancel the
  /// subscription to stop early.
  Stream<TpSearchMatch> run(String root, TpSearchOptions options) {
    final run = _ContentSearchRun();
    _run = run;
    return run.start(root, options);
  }

  /// Stops the walk and releases the worker. The worker frees its native
  /// handle itself; see the library doc.
  void cancel() => _run?.cancel();
}

class _ContentSearchRun {
  final StreamController<TpSearchMatch> events = StreamController();
  Isolate? _isolate;
  ReceivePort? _reply;
  SendPort? _control;
  bool _cancelled = false;

  Stream<TpSearchMatch> start(String root, TpSearchOptions options) {
    events.onCancel = () => _cancel(closeEvents: false);
    unawaited(_spawn(root, options));
    return events.stream;
  }

  void cancel() => _cancel(closeEvents: true);

  Future<void> _spawn(String root, TpSearchOptions options) async {
    final reply = ReceivePort();
    _reply = reply;
    reply.listen((Object? message) {
      switch (message) {
        case _SearchWorkerReady(:final control):
          _control = control;
          // Cancelled while the isolate was still starting up.
          if (_cancelled) control.send(_kCancelMessage);
        case _SearchWorkerBatch(:final matches):
          if (_cancelled) return;
          for (final match in matches) {
            events.add(match);
          }
        case _SearchWorkerFailed(:final message):
          if (_cancelled) return;
          events.addError(StateError(message));
          _finish();
        case _SearchWorkerDone():
          if (_cancelled) return;
          _finish();
      }
    });
    try {
      _isolate = await Isolate.spawn(
        _searchWorkerMain,
        _SearchWorkerStart(reply: reply.sendPort, root: root, options: options),
      );
      if (_cancelled) _control?.send(_kCancelMessage);
    } on Object catch (error, stack) {
      if (_cancelled) return;
      events.addError(error, stack);
      _finish();
    }
  }

  void _cancel({required bool closeEvents}) {
    if (_cancelled) return;
    _cancelled = true;
    _control?.send(_kCancelMessage);
    _releaseWorker();
    if (closeEvents && !events.isClosed) unawaited(events.close());
  }

  void _finish() {
    _releaseWorker();
    if (!events.isClosed) unawaited(events.close());
  }

  void _releaseWorker() {
    _reply?.close();
    _reply = null;
    _control = null;
    _isolate = null;
  }
}

// ---------------------------------------------------------------------------
// File index
// ---------------------------------------------------------------------------

class _FileIndexWorkerStart {
  const _FileIndexWorkerStart(this.reply);

  final SendPort reply;
}

class _FileIndexWorkerReady {
  const _FileIndexWorkerReady(this.control);

  final SendPort control;
}

class _FileIndexBuildRequest {
  const _FileIndexBuildRequest({
    required this.id,
    required this.root,
    required this.options,
  });

  final int id;
  final String root;
  final TpFileIndexOptions options;
}

class _FileIndexQueryRequest {
  const _FileIndexQueryRequest({
    required this.id,
    required this.query,
    required this.mode,
    required this.limit,
  });

  final int id;
  final String query;
  final TpFileMatchMode mode;
  final int limit;
}

class _FileIndexDirsRequest {
  const _FileIndexDirsRequest({
    required this.id,
    required this.query,
    required this.limit,
  });

  final int id;
  final String query;
  final int limit;
}

class _FileIndexCloseRequest {
  const _FileIndexCloseRequest();
}

class _FileIndexBuildReply {
  const _FileIndexBuildReply(this.id, this.error);

  final int id;

  /// Null on success, otherwise the failure message.
  final String? error;
}

class _FileIndexQueryReply {
  const _FileIndexQueryReply(this.id, this.hits, this.truncated, this.error);

  final int id;
  final List<TpFileHit>? hits;
  final bool truncated;
  final String? error;
}

class _FileIndexDirsReply {
  const _FileIndexDirsReply(this.id, this.paths, this.error);

  final int id;
  final List<String>? paths;
  final String? error;
}

Future<void> _fileIndexWorkerMain(_FileIndexWorkerStart start) async {
  final control = ReceivePort();
  start.reply.send(_FileIndexWorkerReady(control.sendPort));
  final index = TpFileIndex();
  Future<void>? building;
  try {
    await for (final message in control) {
      switch (message) {
        case _FileIndexBuildRequest(:final id, :final root, :final options):
          if (building != null) {
            start.reply.send(
              _FileIndexBuildReply(id, 'a build is already running'),
            );
            continue;
          }
          final reply = start.reply;
          final future = _runFileIndexBuild(index, reply, id, root, options);
          building = future;
          unawaited(future.whenComplete(() => building = null));
        case _FileIndexQueryRequest(
          :final id,
          :final query,
          :final mode,
          :final limit,
        ):
          if (building != null) {
            start.reply.send(
              _FileIndexQueryReply(id, null, false, 'the index is building'),
            );
            continue;
          }
          try {
            final hits = index.query(query, mode: mode, limit: limit);
            start.reply.send(
              _FileIndexQueryReply(id, hits, index.truncated, null),
            );
          } on Object catch (error) {
            start.reply.send(_FileIndexQueryReply(id, null, false, '$error'));
          }
        case _FileIndexDirsRequest(:final id, :final query, :final limit):
          if (building != null) {
            start.reply.send(
              _FileIndexDirsReply(id, null, 'the index is building'),
            );
            continue;
          }
          try {
            final paths = index.queryDirectories(query, limit: limit);
            start.reply.send(_FileIndexDirsReply(id, paths, null));
          } on Object catch (error) {
            start.reply.send(_FileIndexDirsReply(id, null, '$error'));
          }
        case _FileIndexCloseRequest():
          // Abort any in-flight walk before freeing the handle.
          index.cancel();
          final inFlight = building;
          if (inFlight != null) await inFlight;
          index.dispose();
          control.close();
          return;
      }
    }
  } finally {
    control.close();
  }
}

Future<void> _runFileIndexBuild(
  TpFileIndex index,
  SendPort reply,
  int id,
  String root,
  TpFileIndexOptions options,
) async {
  try {
    await index.build(root, options);
    reply.send(_FileIndexBuildReply(id, null));
  } on Object catch (error) {
    reply.send(_FileIndexBuildReply(id, '$error'));
  }
}

/// Owns a [TpFileIndex] on a worker isolate.
///
/// The index is built once and then queried repeatedly; keeping it on the same
/// worker reuses the native handle and keeps the fuzzy scoring/sorting of every
/// indexed file off the UI isolate.
class IsolatedFileIndex {
  Isolate? _isolate;
  ReceivePort? _reply;
  SendPort? _control;
  Future<void>? _starting;
  Completer<void>? _ready;
  final Map<int, Completer<String?>> _builds = {};
  final Map<int, Completer<List<TpFileHit>>> _queries = {};
  final Map<int, Completer<List<String>>> _dirQueries = {};
  int _nextId = 0;
  bool _built = false;
  bool _truncated = false;

  bool get isBuilt => _built;
  bool get truncated => _truncated;

  /// Builds (or rebuilds) the index rooted at [root] on the worker isolate.
  Future<void> build(
    String root, [
    TpFileIndexOptions options = const TpFileIndexOptions(),
  ]) async {
    await _ensureStarted();
    final id = ++_nextId;
    final completer = Completer<String?>();
    _builds[id] = completer;
    _control!.send(
      _FileIndexBuildRequest(id: id, root: root, options: options),
    );
    final error = await completer.future;
    if (error != null) throw StateError(error);
    _built = true;
  }

  /// Returns matching indexed files, computed on the worker isolate.
  Future<List<TpFileHit>> query(
    String query, {
    TpFileMatchMode mode = TpFileMatchMode.fuzzy,
    int limit = 50,
  }) async {
    if (!_built) throw StateError('file index has not been built');
    await _ensureStarted();
    final id = ++_nextId;
    final completer = Completer<List<TpFileHit>>();
    _queries[id] = completer;
    _control!.send(
      _FileIndexQueryRequest(id: id, query: query, mode: mode, limit: limit),
    );
    return completer.future;
  }

  /// Returns matching directory paths, computed on the worker isolate.
  Future<List<String>> queryDirectories(String query, {int limit = 20}) async {
    if (!_built) throw StateError('file index has not been built');
    await _ensureStarted();
    final id = ++_nextId;
    final completer = Completer<List<String>>();
    _dirQueries[id] = completer;
    _control!.send(_FileIndexDirsRequest(id: id, query: query, limit: limit));
    return completer.future;
  }

  /// Tears the worker down and frees the native index.
  void dispose() {
    _built = false;
    _truncated = false;
    _control?.send(const _FileIndexCloseRequest());
    _control = null;
    _releaseWorker();
    _failPending('file index disposed');
  }

  Future<void> _ensureStarted() {
    final started = _starting;
    if (started != null) return started;
    final future = _startWorker();
    _starting = future;
    return future;
  }

  Future<void> _startWorker() async {
    final reply = ReceivePort();
    final ready = Completer<void>();
    _reply = reply;
    _ready = ready;
    reply.listen(_onMessage);
    try {
      _isolate = await Isolate.spawn(
        _fileIndexWorkerMain,
        _FileIndexWorkerStart(reply.sendPort),
      );
      await ready.future;
      if (_control == null) {
        // Disposed while the isolate was still starting up: nothing will ever
        // talk to it, so stop it instead of leaking an idle worker.
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        throw StateError('file index worker was released');
      }
    } on Object {
      _releaseWorker();
      _starting = null;
      rethrow;
    }
  }

  void _onMessage(Object? message) {
    switch (message) {
      case _FileIndexWorkerReady(:final control):
        _control = control;
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
      case _FileIndexBuildReply(:final id, :final error):
        final completer = _builds.remove(id);
        if (completer == null || completer.isCompleted) return;
        completer.complete(error);
      case _FileIndexQueryReply(
        :final id,
        :final hits,
        :final truncated,
        :final error,
      ):
        final completer = _queries.remove(id);
        if (completer == null || completer.isCompleted) return;
        if (error != null) {
          completer.completeError(StateError(error));
          return;
        }
        _truncated = truncated;
        completer.complete(hits ?? const []);
      case _FileIndexDirsReply(:final id, :final paths, :final error):
        final completer = _dirQueries.remove(id);
        if (completer == null || completer.isCompleted) return;
        if (error != null) {
          completer.completeError(StateError(error));
          return;
        }
        completer.complete(paths ?? const []);
    }
  }

  void _releaseWorker() {
    _reply?.close();
    _reply = null;
    _isolate = null;
    _starting = null;
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  void _failPending(String message) {
    for (final completer in _builds.values) {
      if (!completer.isCompleted) completer.completeError(StateError(message));
    }
    for (final completer in _queries.values) {
      if (!completer.isCompleted) completer.completeError(StateError(message));
    }
    for (final completer in _dirQueries.values) {
      if (!completer.isCompleted) completer.completeError(StateError(message));
    }
    _builds.clear();
    _queries.clear();
    _dirQueries.clear();
  }
}
