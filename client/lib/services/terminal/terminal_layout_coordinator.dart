import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Coordinates PTY resize across all [TerminalResizeController] instances during
/// structural layout changes (sidebar collapse, divider drag, worktree switch,
/// tab open/close, split create/destroy).
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
/// One instance per app, provided via DI. Controllers auto-register on mount
/// and unregister on dispose.
class TerminalLayoutCoordinator {
  final Set<TerminalResizeController> _controllers = {};

  /// Register a controller. Called when a [TerminalView] mounts.
  void register(TerminalResizeController controller) {
    _controllers.add(controller);
  }

  /// Unregister a controller. Called when a [TerminalView] disposes.
  void unregister(TerminalResizeController controller) {
    _controllers.remove(controller);
  }

  /// Whether any controllers are registered.
  bool get hasControllers => _controllers.isNotEmpty;

  /// Run [action] while PTY resizes are held for all registered controllers.
  /// After [action] completes, flush the final grid to the PTY.
  ///
  /// If [action] is asynchronous, PTY resizes remain held until it completes.
  /// If [action] throws, held resizes are cancelled (not flushed).
  Future<void> runLayoutTransaction(
    Future<void> Function() action, {
    bool flush = true,
  }) async {
    for (final c in _controllers) {
      c.beginTransaction();
    }
    try {
      await action();
    } catch (_) {
      // Cancelled: discard queued resizes.
      for (final c in _controllers) {
        c.endTransaction(flush: false);
      }
      rethrow;
    }
    for (final c in _controllers) {
      c.endTransaction(flush: flush);
    }
  }

  /// Synchronous variant for purely synchronous layout changes (e.g. immediate
  /// setState that doesn't await anything).
  ///
  /// Matches [runLayoutTransaction]'s cancel semantics: if [action] throws, the
  /// held resizes are discarded (`flush: false`) before the error propagates,
  /// so a failed layout change never pushes a half-applied grid to the PTY.
  void runLayoutTransactionSync(
    void Function() action, {
    bool flush = true,
  }) {
    for (final c in _controllers) {
      c.beginTransaction();
    }
    try {
      action();
    } catch (_) {
      for (final c in _controllers) {
        c.endTransaction(flush: false);
      }
      rethrow;
    }
    for (final c in _controllers) {
      c.endTransaction(flush: flush);
    }
  }

  /// Begin a transaction on all controllers. Use with [endAllTransactions]
  /// for multi-frame operations like divider drag where the action spans
  /// from a drag-start callback to a drag-end callback.
  void beginAllTransactions() {
    for (final c in _controllers) {
      c.beginTransaction();
    }
  }

  /// End transactions on all controllers, flushing queued PTY resizes if
  /// [flush] is true.
  void endAllTransactions({bool flush = true}) {
    for (final c in _controllers) {
      c.endTransaction(flush: flush);
    }
  }

  /// Immediate flush for all controllers — ensures every pane's PTY is at the
  /// current grid. Used after font-zoom, theme change, or any synchronous
  /// layout change that should take effect right now (similar to orca's
  /// `SYNC_FIT_PANES_EVENT` path for layout-effect pre-paint fit).
  void flushAllImmediate() {
    for (final c in _controllers) {
      c.commitNow();
    }
  }

  /// Cancel all held transactions in all controllers.
  void cancelAllTransactions() {
    for (final c in _controllers) {
      c.endTransaction(flush: false);
    }
  }

  /// Cancel any held transactions and forget all controllers.
  ///
  /// Does **not** dispose the registered controllers: their lifetime is owned
  /// by the host (the chat workbench / workspace panel that created them), which
  /// disposes each controller when it swaps the active engine or unmounts.
  /// Disposing them here too would double-dispose.
  void dispose() {
    cancelAllTransactions();
    _controllers.clear();
  }
}
