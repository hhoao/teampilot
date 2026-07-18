import 'dart:async';

import '../../cubits/ai_history_cubit.dart';
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
    required AiHistoryCubit cubit,
    required Filesystem Function() fs,
    required Future<AiHistoryWatchMeta?> Function() resolveWatchMeta,
    AiHistoryLiveRefreshSignalFactory? createSignal,
  }) : _cubit = cubit,
       _fs = fs,
       _resolveWatchMeta = resolveWatchMeta,
       _createSignal = createSignal ?? _defaultCreateSignal;

  final AiHistoryCubit _cubit;
  final Filesystem Function() _fs;
  final Future<AiHistoryWatchMeta?> Function() _resolveWatchMeta;
  final AiHistoryLiveRefreshSignalFactory _createSignal;

  AiHistoryWatchMeta? _meta;
  TranscriptChangeSignalHandle? _signal;
  bool _started = false;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refreshNow();
    if (!_started) return;
    await _attachSignal();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _reloadQueued = false;
    final signal = _signal;
    _signal = null;
    await signal?.stop();
  }

  /// Force one softReload (e.g. return-to-History).
  Future<void> refreshNow() => _requestReload();

  Future<void> _attachSignal() async {
    await _signal?.stop();
    if (!_started) return;

    final filesystem = _fs();
    final pollInterval = filesystem is FsWatcher
        ? const Duration(milliseconds: 750)
        : const Duration(milliseconds: 1200);

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
        _meta = await _resolveWatchMeta();
        if (!_started) break;
        await _cubit.softReload();
      } while (_reloadQueued && _started);
    } finally {
      _reloadInFlight = false;
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
