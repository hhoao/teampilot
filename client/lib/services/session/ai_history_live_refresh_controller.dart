import 'dart:async';

import '../../cubits/ai_history_seat.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'ai_history_watch_meta.dart';
import 'transcript_change_signal.dart';

/// Narrow start/stop surface for [TranscriptChangeSignal] (and test fakes).
abstract interface class TranscriptChangeSignalHandle {
  Future<void> start();
  Future<void> stop();
}

typedef AiHistoryLiveRefreshSignalFactory =
    TranscriptChangeSignalHandle Function({
      required Filesystem fs,
      required String? Function() watchRoot,
      required List<String> Function() cacheTokenPaths,
      required void Function() onChanged,
      required Duration pollInterval,
    });

/// Owns transcript watch/poll while History is visible; coalesces softReloads.
class AiHistoryLiveRefreshController {
  AiHistoryLiveRefreshController({
    required AiHistorySeat seat,
    required Filesystem Function() fs,
    required Future<AiHistoryWatchMeta?> Function() resolveWatchMeta,
    AiHistoryLiveRefreshSignalFactory? createSignal,
    Duration? metaRetryInterval,
  }) : _seat = seat,
       _fs = fs,
       _resolveWatchMeta = resolveWatchMeta,
       _createSignal = createSignal ?? _defaultCreateSignal,
       _metaRetryIntervalOverride = metaRetryInterval;

  final AiHistorySeat _seat;
  final Filesystem Function() _fs;
  final Future<AiHistoryWatchMeta?> Function() _resolveWatchMeta;
  final AiHistoryLiveRefreshSignalFactory _createSignal;
  final Duration? _metaRetryIntervalOverride;

  AiHistoryWatchMeta? _meta;
  TranscriptChangeSignalHandle? _signal;
  Timer? _metaRetryTimer;
  bool _started = false;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;

  /// True while [start] / [ensureStarted] has begun and [stop] has not finished.
  bool get isActive => _started;

  /// Starts watching transcript changes.
  ///
  /// When [skipInitialRefresh] is true, attaches the change signal without
  /// calling [refreshNow]. Use after the caller already soft-reloaded (e.g.
  /// [AiHistoryCubit.softReloadOrLoad] on History remount) so we do not stack
  /// a second softReload.
  Future<void> start({bool skipInitialRefresh = false}) async {
    if (_started) return;
    _started = true;
    if (!skipInitialRefresh) {
      await refreshNow();
    }
    if (!_started) return;
    await _attachSignal();
    _syncMetaRetry();
  }

  /// Idempotent alias for [start] (History continue / remount callers).
  Future<void> ensureStarted({bool skipInitialRefresh = false}) =>
      start(skipInitialRefresh: skipInitialRefresh);

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _reloadQueued = false;
    _cancelMetaRetry();
    final signal = _signal;
    _signal = null;
    await signal?.stop();
  }

  /// Force one softReload (e.g. return-to-History).
  Future<void> refreshNow() => _requestReload();

  Duration _pollIntervalFor(Filesystem filesystem) {
    return filesystem is FsWatcher
        ? const Duration(milliseconds: 750)
        : const Duration(milliseconds: 1200);
  }

  Future<void> _attachSignal() async {
    await _signal?.stop();
    if (!_started) return;

    final filesystem = _fs();
    final pollInterval = _pollIntervalFor(filesystem);

    _signal = _createSignal(
      fs: filesystem,
      watchRoot: () => _meta?.changeWatchRoot,
      cacheTokenPaths: () => _meta?.cacheTokenPaths ?? const [],
      onChanged: _onTranscriptChanged,
      pollInterval: pollInterval,
    );
    await _signal!.start();
  }

  void _onTranscriptChanged() {
    if (!_started) return;
    unawaited(_requestReload());
  }

  void _cancelMetaRetry() {
    _metaRetryTimer?.cancel();
    _metaRetryTimer = null;
  }

  void _syncMetaRetry() {
    if (!_started || _meta != null) {
      _cancelMetaRetry();
      return;
    }
    if (_metaRetryTimer != null) return;
    final interval =
        _metaRetryIntervalOverride ?? _pollIntervalFor(_fs());
    _metaRetryTimer = Timer.periodic(interval, (_) {
      if (!_started || _meta != null) {
        _cancelMetaRetry();
        return;
      }
      unawaited(_requestReload());
    });
  }

  bool _metaWatchChanged(AiHistoryWatchMeta? previous, AiHistoryWatchMeta next) {
    if (previous == null) return true;
    if (previous.changeWatchRoot != next.changeWatchRoot) return true;
    final a = previous.cacheTokenPaths;
    final b = next.cacheTokenPaths;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  Future<void> _requestReload() async {
    if (!_started) return;
    if (_reloadInFlight) {
      _reloadQueued = true;
      return;
    }
    _reloadInFlight = true;
    try {
      do {
        _reloadQueued = false;
        if (!_started) break;
        final previous = _meta;
        try {
          final next = await _resolveWatchMeta();
          if (!_started) break;
          if (next != null) {
            // Rearm only when a live signal already exists and watch targets
            // change (null→meta or root/paths). Start attaches after refreshNow.
            final shouldRearm =
                _signal != null && _metaWatchChanged(previous, next);
            _meta = next;
            await _seat.softReload();
            if (!_started) break;
            if (shouldRearm) {
              await _attachSignal();
            }
          } else {
            await _seat.softReload();
          }
        } on Object catch (e, st) {
          // Keep last [_meta]; softReload errors are already swallowed in seat.
          appLogger.w(
            '[ai-history-live-refresh] reload failed: $e',
            error: e,
            stackTrace: st,
          );
        }
        _syncMetaRetry();
      } while (_reloadQueued && _started);
    } finally {
      _reloadInFlight = false;
    }
    if (_reloadQueued && _started) {
      unawaited(_requestReload());
    }
  }

  static TranscriptChangeSignalHandle _defaultCreateSignal({
    required Filesystem fs,
    required String? Function() watchRoot,
    required List<String> Function() cacheTokenPaths,
    required void Function() onChanged,
    required Duration pollInterval,
  }) {
    return _TranscriptChangeSignalAdapter(
      TranscriptChangeSignal(
        fs: fs,
        watchRoot: watchRoot,
        cacheTokenPaths: cacheTokenPaths,
        onChanged: onChanged,
        pollInterval: pollInterval,
      ),
    );
  }
}

final class _TranscriptChangeSignalAdapter
    implements TranscriptChangeSignalHandle {
  _TranscriptChangeSignalAdapter(this._inner);

  final TranscriptChangeSignal _inner;

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> stop() => _inner.stop();
}
