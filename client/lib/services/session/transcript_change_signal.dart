import 'dart:async';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'ai_history_cache_token.dart';

/// Emits when on-disk transcript content may have changed.
///
/// Prefer native [FsWatcher.watchTree] on the parent directory of each
/// [cacheTokenPaths] file (Linux [Directory.watch] is not recursive — a
/// too-high [watchRoot] would miss nested JSONL appends). Fall back to
/// [watchRoot], then to polling [cacheTokenPaths] via [Filesystem.stat].
///
/// The token poll ALWAYS runs alongside the watches: macOS FSEvents withholds
/// modify events for writes made through a long-lived open file descriptor
/// and only flushes them when the writer closes the fd / exits (verified
/// 2026-09-10 with a kept-open-append node process: zero events while alive,
/// one coalesced burst ~200ms after exit). CLIs that write per-event with
/// open→append→close (Claude Code) deliver promptly; codex keeps its rollout
/// handle open for the whole session, so watch-only mode never saw its
/// appends. The cache-token guard dedupes the reloads, so the extra stat per
/// interval is the only cost of the belt-and-suspenders pair.
class TranscriptChangeSignal {
  TranscriptChangeSignal({
    required Filesystem fs,
    required String? Function() watchRoot,
    required List<String> Function() cacheTokenPaths,
    required void Function() onChanged,
    Duration watchDebounce = const Duration(milliseconds: 150),
    Duration pollInterval = const Duration(milliseconds: 750),
  }) : _fs = fs,
       _watchRoot = watchRoot,
       _cacheTokenPaths = cacheTokenPaths,
       _onChanged = onChanged,
       _watchDebounce = watchDebounce,
       _pollInterval = pollInterval;

  final Filesystem _fs;
  final String? Function() _watchRoot;
  final List<String> Function() _cacheTokenPaths;
  final void Function() _onChanged;
  final Duration _watchDebounce;
  final Duration _pollInterval;

  bool _started = false;
  final List<FsTreeWatch> _treeWatches = [];
  final List<StreamSubscription<FsChangeEvent>> _watchSubs = [];
  Timer? _debounceTimer;
  Timer? _pollTimer;
  String? _lastToken;
  bool _watchStreamDied = false;
  Future<void> _chain = Future<void>.value();
  Future<void> _watchTeardownChain = Future<void>.value();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _arm();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _stopWatch();
    _lastToken = null;
    _watchStreamDied = false;
    _chain = Future<void>.value();
    final teardown = _watchTeardownChain;
    _watchTeardownChain = Future<void>.value();
    await teardown;
  }

  Future<void> _arm() async {
    if (!_started) return;
    if (_fs is FsWatcher) {
      final dirs = _watchDirs();
      if (dirs.isNotEmpty) {
        appLogger.d('[live-refresh-diag] signal arm watch dirs=$dirs');
        await _startWatches(dirs);
        // Keep the token poll running as a fallback: macOS FSEvents withholds
        // modify events for writes through long-lived open fds until the
        // writer exits (codex keeps its rollout handle open all session).
        // The token guard dedupes the reloads, so the extra stat every
        // interval is the only cost.
        _startPoll();
        return;
      }
    }
    appLogger.d('[live-refresh-diag] signal arm poll (no watch dirs)');
    _startPoll();
  }

  /// Directories that Linux inotify can actually see file appends in: parents
  /// of located transcript files first, then the coarse [watchRoot].
  List<String> _watchDirs() {
    final List<String> paths;
    try {
      paths = _cacheTokenPaths();
    } on Object {
      return const [];
    }
    final dirs = <String>{};
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty) continue;
      final dir = _fs.pathContext.dirname(trimmed).trim();
      if (dir.isNotEmpty) dirs.add(dir);
    }
    if (dirs.isNotEmpty) return dirs.toList(growable: false);
    final root = _watchRoot()?.trim() ?? '';
    if (root.isNotEmpty) return [root];
    return const [];
  }

  Future<void> _startWatches(List<String> dirs) async {
    await _stopWatch();
    if (!_started) return;
    final watcher = _fs as FsWatcher;
    try {
      for (final dir in dirs) {
        final treeWatch = watcher.watchTree(dir);
        _treeWatches.add(treeWatch);
        _watchSubs.add(
          treeWatch.events.listen(
            (_) => _scheduleDebouncedNotify(),
            onDone: () {
              // Dart's Directory.watch (Windows) closes silently after native
              // buffer overflows instead of erroring. Without a fallback the
              // signal goes permanently blind and live refresh never fires.
              _onWatchStreamClosed();
            },
            cancelOnError: false,
          ),
        );
      }
      if (_treeWatches.isEmpty) _startPoll();
    } on Object {
      await _stopWatch();
      _startPoll();
    }
  }

  /// A watch event stream died (done or error). Fall back to polling for the
  /// rest of this signal instance: re-arming the watch from the poll tick
  /// cannot distinguish a dead backend from a healthy one, and would loop on
  /// re-subscribing to the closed stream. Controller-level re-arm (meta
  /// change) builds a fresh signal instead.
  ///
  /// Synchronous: waiting on watch teardown from inside the close callback
  /// can park completion on a real-timer microtask that fake_async (and the
  /// app frame loop under load) will not flush in time — the poll must arm
  /// immediately. Dead watches are torn down on the serialized chain.
  void _onWatchStreamClosed() {
    if (!_started) return;
    if (_pollTimer != null) return;
    _watchStreamDied = true;
    _startPoll();
    final watches = List<FsTreeWatch>.of(_treeWatches);
    _treeWatches.clear();
    final subs = List<StreamSubscription<FsChangeEvent>>.of(_watchSubs);
    _watchSubs.clear();
    _enqueueWatchTeardown(watches, subs);
  }

  void _enqueueWatchTeardown(
    List<FsTreeWatch> watches,
    List<StreamSubscription<FsChangeEvent>> subs,
  ) {
    _watchTeardownChain = _watchTeardownChain.then((_) async {
      for (final treeWatch in watches) {
        await treeWatch.close();
      }
      for (final sub in subs) {
        await sub.cancel();
      }
    }).catchError((_) {});
  }

  Future<void> _stopWatch() async {
    final watches = List<FsTreeWatch>.of(_treeWatches);
    _treeWatches.clear();
    final subs = List<StreamSubscription<FsChangeEvent>>.of(_watchSubs);
    _watchSubs.clear();
    // Close the tree watch before awaiting subscription cancel so teardown
    // still completes under fake_async when cancel yields oddly.
    for (final treeWatch in watches) {
      await treeWatch.close();
    }
    for (final sub in subs) {
      await sub.cancel();
    }
  }

  void _scheduleDebouncedNotify() {
    if (!_started) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_watchDebounce, () {
      if (!_started) return;
      appLogger.d('[live-refresh-diag] signal watch event → notify');
      _onChanged();
    });
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _enqueuePollTick());
    // Immediate first tick so late-locate paths are observed without waiting
    // a full interval after start.
    _enqueuePollTick();
  }

  void _enqueuePollTick() {
    _chain = _chain.then((_) => _pollTick()).catchError((_) {});
  }

  Future<void> _pollTick() async {
    if (!_started) return;

    // Late locate: attach watches once cacheTokenPaths appear — the poll
    // keeps running as the fallback either way (see [_arm]). Skip when a
    // watch stream already died: re-subscribing to the closed stream would
    // loop, so polling stays the fallback for this instance.
    if (!_watchStreamDied && _fs is FsWatcher && _treeWatches.isEmpty) {
      final dirs = _watchDirs();
      if (dirs.isNotEmpty) {
        await _startWatches(dirs);
      }
    }

    final token = await _computeToken();
    if (!_started) return;
    if (token == _lastToken) return;

    final previous = _lastToken;
    _lastToken = token;
    // First observation: establish empty baseline without notifying.
    if (previous == null && token.isEmpty) return;
    appLogger.d(
      '[live-refresh-diag] signal token changed → notify '
      '(prev=${previous == null ? 'null' : 'set'})',
    );
    _onChanged();
  }

  Future<String> _computeToken() async {
    final paths = _cacheTokenPaths();
    if (paths.isEmpty) return '';

    final parts = <String>[];
    for (final path in paths) {
      final st = await _fs.stat(path);
      if (!st.exists || st.kind != FsEntityKind.file) continue;
      parts.add(
        await aiHistoryPathCacheToken(
          fs: _fs,
          path: path,
          byteLength: st.size ?? 0,
        ),
      );
    }
    return parts.join('\n');
  }
}
