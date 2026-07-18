import 'dart:async';

import '../io/filesystem.dart';
import 'ai_history_cache_token.dart';

/// Emits when on-disk transcript content may have changed.
///
/// Prefer native [FsWatcher.watchTree] when available and [watchRoot] is known;
/// otherwise poll [cacheTokenPaths] via [Filesystem.stat] tokens.
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
  FsTreeWatch? _treeWatch;
  StreamSubscription<FsChangeEvent>? _watchSub;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  String? _lastToken;
  Future<void> _chain = Future<void>.value();

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
    _chain = Future<void>.value();
  }

  Future<void> _arm() async {
    if (!_started) return;
    final root = _watchRoot()?.trim();
    if (_fs is FsWatcher && root != null && root.isNotEmpty) {
      await _startWatch(root);
      return;
    }
    _startPoll();
  }

  Future<void> _startWatch(String root) async {
    if (_treeWatch != null || _watchSub != null) {
      await _stopWatch();
      if (!_started) return;
    }
    final watcher = _fs as FsWatcher;
    try {
      final treeWatch = watcher.watchTree(root);
      _treeWatch = treeWatch;
      _watchSub = treeWatch.events.listen(
        (_) => _scheduleDebouncedNotify(),
        cancelOnError: false,
      );
    } on Object {
      // Fall back to polling when watch setup fails.
      _startPoll();
    }
  }

  Future<void> _stopWatch() async {
    final sub = _watchSub;
    _watchSub = null;
    final treeWatch = _treeWatch;
    _treeWatch = null;
    // Close the tree watch before awaiting subscription cancel so teardown
    // still completes under fake_async when cancel yields oddly.
    await treeWatch?.close();
    await sub?.cancel();
  }

  void _scheduleDebouncedNotify() {
    if (!_started) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_watchDebounce, () {
      if (!_started) return;
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

    final root = _watchRoot()?.trim();
    if (_fs is FsWatcher && root != null && root.isNotEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
      await _startWatch(root);
      return;
    }

    final token = await _computeToken();
    if (!_started) return;
    if (token == _lastToken) return;

    final previous = _lastToken;
    _lastToken = token;
    // First observation: establish empty baseline without notifying.
    if (previous == null && token.isEmpty) return;
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
