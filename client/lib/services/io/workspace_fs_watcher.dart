import 'dart:async';

import 'package:path/path.dart' as p;

import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import 'filesystem.dart';

/// Watches a workspace [root] for filesystem changes and exposes a single
/// debounced change signal that multiple panels (file tree, source control)
/// can subscribe to.
///
/// A single watcher per workspace root is intentional: it keeps one recursive
/// OS watch alive instead of one per panel (relevant on Linux where each
/// watched subdirectory consumes an inotify descriptor), and centralises the
/// debounce so a burst of writes from an agent collapses into one refresh.
///
/// Each [onChanged] event carries the set of directory paths whose listing
/// changed, so consumers can reload just those folders instead of the whole
/// tree. An **empty set** means "scope unknown — do a full refresh" (emitted by
/// [poke]).
///
/// When the backing [Filesystem] cannot watch (e.g. SFTP, which has no watch
/// primitive), [isSupported] is false and disk events never arrive — callers
/// keep their existing manual / polling refresh, and [poke] is the change path.
class WorkspaceFsWatcher {
  WorkspaceFsWatcher({
    required Filesystem fs,
    required this.root,
    this.debounce = const Duration(milliseconds: 400),
    bool autoStart = false,
  }) : _watcher = debugDisable || fs is! FsWatcher ? null : fs as FsWatcher,
       _pathContext = fs.pathContext {
    if (autoStart && !debugDisable && root.isNotEmpty) {
      _attachNativeWatch();
    }
  }

  /// When true, skips native watch setup (widget tests use a process-free fs).
  static bool debugDisable = false;

  final String root;
  final Duration debounce;
  final FsWatcher? _watcher;
  final p.Context _pathContext;

  /// Directory names whose churn is pure noise — filtered before they reach the
  /// debounce accumulator so dependency installs and build outputs don't drive
  /// refreshes. `.git` is intentionally NOT here: the source-control panel must
  /// see index/HEAD/ref changes from terminal git commands. (Hidden `.git`
  /// entries are never in the file tree's cache, so they cost it nothing.)
  static const _ignoredSegments = {'node_modules', '.dart_tool', '.gradle'};

  final _controller = StreamController<Set<String>>.broadcast();
  FsTreeWatch? _treeWatch;
  StreamSubscription<FsChangeEvent>? _sub;
  Future<void> _watchChain = Future<void>.value();
  Timer? _debounceTimer;
  final Set<String> _pendingDirs = {};
  bool _pendingFull = false;
  bool _disposed = false;
  bool _suspended = false;

  /// Whether the backing filesystem can deliver change events at all.
  bool get isSupported => _watcher != null;

  /// Fires (debounced) on disk changes. Payload is the set of changed directory
  /// paths; an empty set means "full refresh" (see [poke]).
  Stream<Set<String>> get onChanged => _controller.stream;

  /// Requests a full refresh from an out-of-band activity signal (e.g. an agent
  /// finished a terminal turn). This is the change path for backends without a
  /// native watch (SFTP/WSL), where [isSupported] is false; on watch-capable
  /// backends it just adds one harmless extra debounced refresh.
  void poke() {
    if (_disposed || _suspended) return;
    _pendingFull = true;
    _scheduleEmit();
  }

  /// Stops native watch + debounce without tearing down [onChanged] subscribers.
  void suspend() {
    if (_disposed) return;
    _suspended = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _enqueueWatchOp(_stopNativeWatch);
    _pendingDirs.clear();
    _pendingFull = false;
  }

  /// Restarts native watch after [suspend].
  void resume() {
    if (_disposed || root.isEmpty) return;
    _enqueueWatchOp(_restartNativeWatch);
  }

  void _enqueueWatchOp(Future<void> Function() op) {
    _watchChain = _watchChain.then((_) => op());
  }

  Future<void> _stopNativeWatch() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final treeWatch = _treeWatch;
    _treeWatch = null;
    await treeWatch?.close();
  }

  void _attachNativeWatch() {
    if (_disposed || _sub != null) return;
    final watcher = _watcher;
    if (watcher == null || root.isEmpty) return;
    try {
      final treeWatch = watcher.watchTree(root);
      _treeWatch = treeWatch;
      _sub = treeWatch.events.listen(
        _onEvent,
        onError: (Object error, StackTrace stack) {
          appLogger.w('Workspace watch failed for $root', error: error);
        },
        cancelOnError: false,
      );
    } on Object catch (error) {
      appLogger.w('Workspace watch could not start for $root', error: error);
    }
  }

  Future<void> _restartNativeWatch() async {
    if (_disposed) return;
    await _stopNativeWatch();
    if (_disposed) return;
    _attachNativeWatch();
    _suspended = false;
  }

  void _onEvent(FsChangeEvent event) {
    if (_suspended || _isIgnored(event.path)) return;
    // The parent directory's listing is what changed (entry added/removed/
    // modified); targeting it lets consumers reload just that folder.
    _pendingDirs.add(_pathContext.dirname(event.path));
    _scheduleEmit();
  }

  bool _isIgnored(String path) {
    for (final segment in _pathContext.split(path)) {
      if (_ignoredSegments.contains(segment)) return true;
    }
    return false;
  }

  void _scheduleEmit() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _emit);
  }

  void _emit() {
    if (_disposed || _suspended || _controller.isClosed) return;
    final batch = _pendingFull
        ? const <String>{}
        : Set<String>.of(_pendingDirs);
    _pendingDirs.clear();
    _pendingFull = false;
    _controller.add(batch);
  }

  void dispose() {
    unawaited(stopAndDispose());
  }

  /// Stops the native watch and closes [onChanged]. Await before starting a
  /// replacement watcher so the prior OS subscription is fully cancelled.
  Future<void> stopAndDispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _stopNativeWatch();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
