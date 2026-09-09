import 'dart:async';

import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../cubits/workbench/workbench_tab_bar.dart';
import '../../repositories/workbench_layout_snapshot_repository.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../storage/workspace_layout.dart';

/// App-lifetime coordinator for workbench split-layout persistence.
///
/// One debounced [WorkbenchCubit.stream] subscription covers every workspace
/// (no per-workspace subscriptions to leak):
///
/// - **Save:** changes mark the workspace dirty; a 500 ms debounce (mirrors
///   the persistence debounce style used by `LayoutCubit` saves) flushes each
///   dirty workspace's center + floating snapshot through its
///   [WorkbenchLayoutSnapshotRepository]. The baseline is seeded from the
///   current state when [start] subscribes — bloc streams do not replay the
///   current state to new listeners (`StreamController.broadcast`), so that
///   seed is the exact equivalent of the "skip the first emission" rule and
///   every *real* emission is diffed. Emissions while a restore is in flight
///   only refresh the diff baseline (the pending dirty set is flushed by a
///   debounce re-armed when the restore completes), and flushes are
///   re-entrancy guarded. A workspace whose bar left the state
///   ([WorkbenchCubit.clearWorkspace]) is dropped from the dirty set and
///   re-armed for a later restore.
/// - **Restore:** [restoreForWorkspace] applies the persisted snapshot once
///   per workspace. The caller must invoke it *after* the workspace's
///   sessions rehydrated (the workspace activation chain awaits
///   `ChatCubit.ensureSessionsForWorkspace` first) so session-id resolution
///   is accurate: session tabs resolve against `ChatCubit.state.sessions`
///   and the open tab store; every other kind resolves true (domain sync
///   strips stale ids on its own, per `WorkbenchShellRunSync` precedent).
///
/// Workspace *removal* needs no wiring here: the existing lifecycle deletes
/// the whole workspace directory (`ChatCubit.deleteWorkspace` →
/// `SessionRepositoryFs.deleteWorkspaceDir`), which contains
/// `workbench-layout.json`.
class WorkbenchLayoutPersistence {
  WorkbenchLayoutPersistence({
    required WorkbenchCubit workbench,
    required ChatCubit chat,
    Filesystem? fs,
    WorkspaceLayout? layout,
  }) : _workbench = workbench,
       _chat = chat,
       _fs = fs ?? AppStorage.fs,
       _layout =
           layout ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  static const Duration saveDebounce = Duration(milliseconds: 500);

  final WorkbenchCubit _workbench;
  final ChatCubit _chat;
  final Filesystem _fs;
  final WorkspaceLayout _layout;

  StreamSubscription<WorkbenchState>? _subscription;
  Timer? _debounce;
  final Map<String, WorkspaceTabBar> _lastBars = {};
  final Set<String> _dirty = {};
  final Set<String> _restored = {};
  final Map<String, Future<void>> _restoreFutures = {};
  final Map<String, WorkbenchLayoutSnapshotRepository> _repositories = {};
  bool _restoreInFlight = false;
  bool _flushInFlight = false;
  bool _flushAgain = false;
  bool _disposed = false;

  /// Starts the debounced save subscription. Idempotent.
  void start() {
    if (_disposed || _subscription != null) return;
    _lastBars
      ..clear()
      ..addAll(_workbench.state.byWorkspace);
    _subscription = _workbench.stream.listen(_onWorkbenchState);
  }

  /// Cancels the subscription and pending debounce.
  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Restores [workspaceId]'s persisted snapshot into the workbench, at most
  /// once per workspace (re-armed when its bar is cleared). No-op when the
  /// workspace has no snapshot, the snapshot is corrupt, or every group was
  /// pruned — the bar keeps its current state in all fallback cases.
  ///
  /// Concurrent callers share the in-flight restore, so `await`ing this from
  /// a deep-link open is deterministic even when the workspace activation
  /// chain kicked the restore off first.
  Future<void> restoreForWorkspace(String workspaceId) async {
    final id = workspaceId.trim();
    if (_disposed || id.isEmpty) return;
    final inFlight = _restoreFutures[id];
    if (inFlight != null) {
      await inFlight;
      return;
    }
    if (_restored.contains(id)) return;
    _restored.add(id);
    _restoreInFlight = true;
    final restore = _repositoryFor(id)
        .restore(_workbench, tabResolves: (tab) => _tabResolves(id, tab))
        .then((_) => _registerRestoredSessionTabs(id));
    _restoreFutures[id] = restore;
    try {
      await restore;
    } finally {
      _restoreInFlight = false;
      _restoreFutures.remove(id);
      // Changes that landed mid-restore were only baseline-refreshed; arm the
      // debounce now so their (post-restore) state still gets persisted.
      if (!_disposed && _dirty.isNotEmpty) {
        _debounce?.cancel();
        _debounce = Timer(saveDebounce, () => unawaited(_flush()));
      }
    }
  }

  /// The snapshot restores the workbench layouts (tab ids on strips) but NOT
  /// the ChatCubit tab runtimes — a session tab that no one re-opened has a
  /// strip entry yet no [ChatTab], so the pane renders its chrome (tab chip,
  /// highlight) over a blank body. Register a minimal, not-connected
  /// [ChatTab] for every restored session tab that resolves to a session but
  /// has no runtime: `WorkbenchBody` then finds its session (history loads
  /// lazily, exactly like a normal unconnected open).
  void _registerRestoredSessionTabs(String workspaceId) {
    if (_disposed) return;
    for (final layout in [
      _workbench.centerLayout(workspaceId),
      _workbench.floatingLayout(workspaceId),
    ]) {
      for (final strip in layout.groups.values) {
        for (final tab in strip.order) {
          if (tab.kind != WorkbenchTabKind.session) continue;
          final sessionId = tab.id;
          if (sessionId.isEmpty || sessionId.startsWith('local-')) continue;
          if (_chat.tabStore.openTabBySessionId(sessionId) != null) continue;
          final session = _chat.state.sessions
              .where(
                (s) =>
                    s.sessionId == sessionId &&
                    s.workspaceId == workspaceId,
              )
              .firstOrNull;
          if (session == null) continue;
          // Title mirrors resolveSessionListTitle's non-localized core
          // (trimmed display; sessionId fallback when empty): the UI
          // projections re-derive titles from ChatState anyway — this feeds
          // the runtime-tab metadata only.
          final title = session.display.trim();
          _chat.registerSessionRuntime(
            ChatTab(
              info: ChatTabInfo(
                id: sessionId,
                title: title.isEmpty ? sessionId : title,
                subtitle: '',
              ),
              cliTeamName: session.cliTeamName,
              workspaceId: workspaceId,
            )..persistedSession = session,
          );
        }
      }
    }
  }

  WorkbenchLayoutSnapshotRepository _repositoryFor(String workspaceId) =>
      _repositories.putIfAbsent(
        workspaceId,
        () => WorkbenchLayoutSnapshotRepository(
          workspaceId: workspaceId,
          fs: _fs,
          layout: _layout,
        ),
      );

  bool _tabResolves(String workspaceId, WorkbenchTabId tab) {
    if (tab.kind != WorkbenchTabKind.session) return true;
    for (final session in _chat.state.sessions) {
      if (session.sessionId == tab.id && session.workspaceId == workspaceId) {
        return true;
      }
    }
    for (final tabInfo in _chat.tabStore.openTabs) {
      if (tabInfo.info.id == tab.id) return true;
    }
    return false;
  }

  void _onWorkbenchState(WorkbenchState state) {
    final bars = state.byWorkspace;
    var changed = false;
    for (final entry in bars.entries) {
      if (_lastBars[entry.key] != entry.value) {
        _dirty.add(entry.key);
        changed = true;
      }
    }
    for (final id in _lastBars.keys) {
      if (!bars.containsKey(id)) {
        // Bar cleared (workspace tab closed): stop persisting and re-arm the
        // restore so reopening the workspace reloads its snapshot.
        _dirty.remove(id);
        _restored.remove(id);
      }
    }
    _lastBars
      ..clear()
      ..addAll(bars);
    if (_restoreInFlight || !changed) return;
    _debounce?.cancel();
    _debounce = Timer(saveDebounce, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    if (_disposed) return;
    if (_flushInFlight) {
      _flushAgain = true;
      return;
    }
    _flushInFlight = true;
    try {
      do {
        _flushAgain = false;
        final ids = _dirty.toList();
        _dirty.clear();
        for (final id in ids) {
          final bar = _workbench.state.byWorkspace[id];
          if (bar == null) continue; // cleared while debounced
          await _repositoryFor(id).save(bar.center, bar.floating);
        }
      } while (_flushAgain);
    } finally {
      _flushInFlight = false;
    }
  }
}
