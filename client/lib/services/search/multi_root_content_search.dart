import 'dart:async';

import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';
import 'content_search_runner.dart';

/// One search slice: a single root directory on one target.
class ContentSearchSlice {
  const ContentSearchSlice({
    required this.fs,
    required this.root,
    required this.label,
  });

  /// The target filesystem backing this root (local, SFTP, …).
  final Filesystem fs;

  /// Absolute root path searched by the slice's runner.
  final String root;

  /// Group-header display name (folder basename).
  final String label;
}

/// A tagged event from one slice: a [match], or that slice's [error].
/// Errors are data, not stream errors — a failing slice never disturbs the
/// others.
class MultiRootSearchEvent {
  const MultiRootSearchEvent.match(this.slice, this.match) : error = null;
  const MultiRootSearchEvent.error(this.slice, this.error) : match = null;

  final ContentSearchSlice slice;
  final TpSearchMatch? match;
  final Object? error;

  bool get isError => error != null;
}

/// Fan-out content search: one [ContentSearchRunner] per [ContentSearchSlice],
/// all slices searched concurrently; matches stream through as they arrive and
/// a failing slice emits a single error event. [cancel] stops every in-flight
/// runner (including the Rust walker behind each engine handle).
class MultiRootContentSearch {
  MultiRootContentSearch({
    required List<ContentSearchSlice> slices,
    ContentSearchRunner Function(ContentSearchSlice slice)? runnerFactory,
  }) : _slices = List.unmodifiable(slices),
       _runnerFactory =
           runnerFactory ??
           ((ContentSearchSlice s) =>
               ContentSearchRunner(fs: s.fs, root: s.root));

  final List<ContentSearchSlice> _slices;
  final ContentSearchRunner Function(ContentSearchSlice slice) _runnerFactory;

  final _runners = <ContentSearchRunner>[];
  final _subscriptions = <StreamSubscription<TpSearchMatch>>[];
  StreamController<MultiRootSearchEvent>? _master;
  var _cancelled = false;

  /// Runs [options] on every slice concurrently and merges the tagged events.
  Stream<MultiRootSearchEvent> run(TpSearchOptions options) {
    final master = _master = StreamController<MultiRootSearchEvent>();
    var pending = _slices.length;
    if (pending == 0) {
      scheduleMicrotask(master.close);
      return master.stream;
    }
    for (final slice in _slices) {
      final runner = _runnerFactory(slice);
      _runners.add(runner);
      _subscriptions.add(
        runner.run(options).listen(
          (match) {
            if (!_cancelled) {
              master.add(MultiRootSearchEvent.match(slice, match));
            }
          },
          onError: (Object e) {
            if (!_cancelled) {
              master.add(MultiRootSearchEvent.error(slice, e));
            }
          },
          onDone: () {
            if (_cancelled) return;
            if (--pending == 0) master.close();
          },
        ),
      );
    }
    return master.stream;
  }

  /// Cancels every in-flight runner and subscription, then closes the merged
  /// stream so consumers awaiting [run] complete normally.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final r in _runners) {
      r.cancel();
    }
    _master?.close();
    _master = null;
  }
}
