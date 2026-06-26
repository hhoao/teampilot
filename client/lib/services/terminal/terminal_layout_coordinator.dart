import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Bracket target for suppressing PTY SIGWINCH during layout animation.
abstract interface class PtyResizeHoldTarget {
  void beginPtyHold();
  void endPtyHold({bool flush = true});
}

/// Adapts [TerminalViewState] to [PtyResizeHoldTarget].
PtyResizeHoldTarget ptyHoldTargetFor(TerminalViewState state) =>
    _TerminalViewHoldTarget(state);

final class _TerminalViewHoldTarget implements PtyResizeHoldTarget {
  _TerminalViewHoldTarget(this._state);

  final TerminalViewState _state;

  @override
  void beginPtyHold() => _state.beginPtyHold();

  @override
  void endPtyHold({bool flush = true}) => _state.endPtyHold(flush: flush);
}

/// Coordinates PTY resize holds across terminal panes during structural layout
/// changes (sidebar collapse, divider drag, worktree switch, tab open/close,
/// split create/destroy).
///
/// Counterpart of orca's `holdPtyResizesForPaneSubtrees` + `SYNC_FIT_PANES_EVENT`.
///
/// Usage:
/// ```dart
/// coordinator.runLayoutTransaction(() {
///   setState(() => _sidebarOpen = !_sidebarOpen);
/// });
/// ```
///
/// One instance per terminal host (e.g. workspace terminal panel). Targets
/// auto-register on mount and unregister on dispose.
class TerminalLayoutCoordinator {
  final Set<PtyResizeHoldTarget> _targets = {};

  /// Register a terminal view. Called when a [TerminalView] mounts.
  void register(PtyResizeHoldTarget target) {
    _targets.add(target);
  }

  /// Unregister a terminal view. Called when a [TerminalView] disposes.
  void unregister(PtyResizeHoldTarget target) {
    _targets.remove(target);
  }

  /// Whether any targets are registered.
  bool get hasTargets => _targets.isNotEmpty;

  /// Run [action] while PTY resizes are held for all registered targets.
  /// After [action] completes, flush the final grid to the PTY.
  ///
  /// If [action] is asynchronous, PTY resizes remain held until it completes.
  /// If [action] throws, held resizes are cancelled (not flushed).
  Future<void> runLayoutTransaction(
    Future<void> Function() action, {
    bool flush = true,
  }) async {
    for (final t in _targets) {
      t.beginPtyHold();
    }
    try {
      await action();
    } catch (_) {
      for (final t in _targets) {
        t.endPtyHold(flush: false);
      }
      rethrow;
    }
    for (final t in _targets) {
      t.endPtyHold(flush: flush);
    }
  }

  /// Synchronous variant for purely synchronous layout changes (e.g. immediate
  /// setState that doesn't await anything).
  void runLayoutTransactionSync(
    void Function() action, {
    bool flush = true,
  }) {
    for (final t in _targets) {
      t.beginPtyHold();
    }
    try {
      action();
    } catch (_) {
      for (final t in _targets) {
        t.endPtyHold(flush: false);
      }
      rethrow;
    }
    for (final t in _targets) {
      t.endPtyHold(flush: flush);
    }
  }

  /// Begin a hold on all targets. Use with [endAllTransactions] for multi-frame
  /// operations like divider drag where the action spans drag-start to drag-end.
  void beginAllTransactions() {
    for (final t in _targets) {
      t.beginPtyHold();
    }
  }

  /// End holds on all targets, flushing queued PTY resizes if [flush] is true.
  void endAllTransactions({bool flush = true}) {
    for (final t in _targets) {
      t.endPtyHold(flush: flush);
    }
  }

  /// Cancel all held transactions in all targets.
  void cancelAllTransactions() {
    for (final t in _targets) {
      t.endPtyHold(flush: false);
    }
  }

  /// Cancel any held transactions and forget all targets.
  ///
  /// Does **not** dispose the registered views: their lifetime is owned by the
  /// host widget that created them.
  void dispose() {
    cancelAllTransactions();
    _targets.clear();
  }
}
