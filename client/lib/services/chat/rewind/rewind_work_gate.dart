import 'dart:async';

/// Coordinates one seat's rewind git directory.
///
/// [runSnapshot] is the in-flight [SeatRewindStore.commitTurn]. Rewind and
/// fork wait for that snapshot before they touch the work tree. [begin] marks
/// a rewind or fork so a later snapshot becomes a no-op.
final class RewindWorkGate {
  final Set<String> _inProgress = {};
  final Map<String, Future<void>> _tails = {};

  /// Cubit hook: a checkpoint, rewind, or fork finished for some seat.
  void Function(String sessionId)? onHistoryChanged;

  bool isInProgress(String gitDir) => _inProgress.contains(gitDir);

  /// Atomically claims [gitDir] for a work-tree mutation.
  ///
  /// Returns false when another rewind already owns it. A separate
  /// `isInProgress` check followed by `begin` would let two callers through.
  bool begin(String gitDir) => _inProgress.add(gitDir);

  void end(String gitDir) => _inProgress.remove(gitDir);

  void noteHistoryChanged(String sessionId) =>
      onHistoryChanged?.call(sessionId);

  Future<void> waitForSnapshot(String gitDir) async {
    final pending = _tails[gitDir];
    if (pending == null) return;
    try {
      await pending;
    } on Object {
      // The snapshot logged its own failure. Restore may still proceed.
    }
  }

  /// Runs [body] as the in-flight snapshot for [gitDir].
  ///
  /// The tail is registered before [body] awaits, so [waitForSnapshot] sees
  /// it. A second call chains behind the first.
  Future<T> runSnapshot<T>(String gitDir, Future<T> Function() body) {
    final done = Completer<void>();
    final previous = _tails[gitDir] ?? Future<void>.value();
    final settled = previous.then<void>((_) {}, onError: (_, _) {});
    final tail = settled.then((_) => done.future);
    _tails[gitDir] = tail;
    return _invoke(gitDir, previous, done, tail, body);
  }

  Future<T> _invoke<T>(
    String gitDir,
    Future<void> previous,
    Completer<void> done,
    Future<void> tail,
    Future<T> Function() body,
  ) async {
    try {
      try {
        await previous;
      } on Object {
        // The previous snapshot failed; this one still runs.
      }
      return await body();
    } finally {
      if (!done.isCompleted) done.complete();
      if (identical(_tails[gitDir], tail)) {
        _tails.remove(gitDir);
      }
    }
  }
}
