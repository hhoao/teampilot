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
    this.reloadMinInterval = const Duration(seconds: 1),
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

  /// 两次 reload 之间的最小间隔;持续输出时把高频变更合并为一次刷新。
  final Duration reloadMinInterval;

  AiHistoryWatchMeta? _meta;
  TranscriptChangeSignalHandle? _signal;
  Timer? _metaRetryTimer;
  DateTime? _lastReloadAt;
  Timer? _throttleTimer;
  bool _started = false;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;

  /// Meta 重试的指数退避指数与"探测已发出、等待返回"标志。
  int _metaRetryBackoff = 0;
  bool _metaProbePending = false;

  /// 在途的 watch-meta 解析(locate 查询链)。probe 与 reload 共享单飞:
  /// 任意时刻每个 controller 最多一条 locate 链,避免
  /// `opencode-sqlite-read` 多链并发。
  Future<AiHistoryWatchMeta?>? _metaResolveInFlight;

  Future<AiHistoryWatchMeta?> _resolveMetaOnce() {
    final existing = _metaResolveInFlight;
    if (existing != null) return existing;
    final future = _resolveWatchMeta();
    _metaResolveInFlight = future;
    future.whenComplete(() {
      if (identical(_metaResolveInFlight, future)) {
        _metaResolveInFlight = null;
      }
    }).ignore();
    return future;
  }

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
      // Mount refresh is not a throttle baseline — throttling only coalesces
      // change/poll-driven reloads after the first live change.
      _lastReloadAt = null;
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
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _lastReloadAt = null;
    _cancelMetaRetry();
    final signal = _signal;
    _signal = null;
    await signal?.stop();
  }

  /// Force one softReload (e.g. return-to-History).
  Future<void> refreshNow() => _requestReload();

  Duration _pollIntervalFor(Filesystem filesystem) {
    return const Duration(milliseconds: 2000);
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
    _metaProbePending = false;
  }

  void _syncMetaRetry() {
    if (!_started || _meta != null) {
      _metaRetryBackoff = 0;
      _cancelMetaRetry();
      return;
    }
    if (_metaRetryTimer != null || _metaProbePending) return;
    _scheduleMetaRetry(resetBackoff: true);
  }

  /// 指数退避重试 watch meta(750ms → 1.5s → 3s → 6s → 12s 封顶)。
  /// 旧实现是每 tick 跑一次完整的 [_requestReload](locate + cache-token
  /// 查询),meta 一直为 null 时会无限期保持 750ms 一轮,让多个 worker
  /// isolate 在空闲会话上常驻存活。
  void _scheduleMetaRetry({required bool resetBackoff}) {
    _cancelMetaRetry();
    if (!_started || _meta != null) return;
    if (resetBackoff) _metaRetryBackoff = 0;
    final base = _metaRetryIntervalOverride ?? _pollIntervalFor(_fs());
    final multiplier = 1 << _metaRetryBackoff.clamp(0, 4);
    _metaRetryTimer = Timer(base * multiplier, () {
      _metaRetryTimer = null;
      if (!_started || _meta != null) return;
      _metaRetryBackoff++;
      _metaProbePending = true;
      unawaited(_probeMetaOnly());
    });
  }

  /// 仅重试 meta 探测,不重跑 seat 软重载;meta 出现后再走一次正常 reload
  /// (此时 attach 变化信号)。
  Future<void> _probeMetaOnly() async {
    try {
      final next = await _resolveMetaOnce();
      if (!_started) return;
      if (next != null) {
        _metaRetryBackoff = 0;
        // 不预置 _meta:交给 _requestReload 以 previous=null 语义 rearm 信号。
        await _requestReload(preResolvedMeta: next);
      } else {
        _scheduleMetaRetry(resetBackoff: false);
      }
    } on Object catch (e, st) {
      appLogger.w(
        '[ai-history-live-refresh] meta probe failed: $e',
        error: e,
        stackTrace: st,
      );
      if (!_started) return;
      _scheduleMetaRetry(resetBackoff: false);
    } finally {
      _metaProbePending = false;
    }
  }

  bool _metaWatchChanged(
    AiHistoryWatchMeta? previous,
    AiHistoryWatchMeta next,
  ) {
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

  Future<void> _requestReload({
    bool skipThrottle = false,
    AiHistoryWatchMeta? preResolvedMeta,
  }) async {
    if (!_started) return;
    if (!skipThrottle) {
      final now = DateTime.now();
      final last = _lastReloadAt;
      if (last != null && now.difference(last) < reloadMinInterval) {
        _reloadQueued = true;
        _throttleTimer ??= Timer(reloadMinInterval - now.difference(last), () {
          _throttleTimer = null;
          if (_started && _reloadQueued) {
            _reloadQueued = false;
            unawaited(_requestReload());
          }
        });
        return;
      }
      _lastReloadAt = now;
    }
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
          // Probe 已解析出 meta 时直接复用,避免同一轮查询链跑两遍;
          // 未预解析时经 [_resolveMetaOnce] 单飞(probe/reload 共享)。
          final next = preResolvedMeta ?? await _resolveMetaOnce();
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
      unawaited(_requestReload(skipThrottle: true));
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
