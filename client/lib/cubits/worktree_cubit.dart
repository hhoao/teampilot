import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/git_worktree.dart';
import '../services/git/git_worktree_service.dart';
import '../services/home_workspace/worktree_ui_prefs_store.dart';
import '../services/workspace/workspace_worktree_store.dart';
import '../utils/session_worktree_grouping.dart';
import '../utils/workspace_path_utils.dart';

/// Narrow seam so tests inject a fake without a real GitWorktreeService.
abstract class WorktreeLister {
  Future<List<GitWorktree>> list(String repoPath);
}

class _GitWorktreeLister implements WorktreeLister {
  _GitWorktreeLister(this._service);
  final GitWorktreeService _service;

  @override
  Future<List<GitWorktree>> list(String repoPath) => _service.list(repoPath);
}

class WorktreeState {
  const WorktreeState({
    this.repoPath = '',
    this.worktrees = const [],
    this.currentWorktreePath = '',
    this.collapsed = const {},
    this.loading = false,
  });

  final String repoPath;
  final List<GitWorktree> worktrees;
  final String currentWorktreePath;
  final Set<String> collapsed;
  final bool loading;

  /// True once there is more than the main worktree (drives grouped vs flat).
  bool get hasMultipleWorktrees => worktrees.length > 1;

  WorktreeState copyWith({
    String? repoPath,
    List<GitWorktree>? worktrees,
    String? currentWorktreePath,
    Set<String>? collapsed,
    bool? loading,
  }) =>
      WorktreeState(
        repoPath: repoPath ?? this.repoPath,
        worktrees: worktrees ?? this.worktrees,
        currentWorktreePath: currentWorktreePath ?? this.currentWorktreePath,
        collapsed: collapsed ?? this.collapsed,
        loading: loading ?? this.loading,
      );
}

/// How [WorkspaceSidebar] lays out the conversation list for the current repo.
enum WorktreeSessionListLayout {
  /// Worktree list not loaded yet — show a placeholder, not a flat list.
  indeterminate,

  /// Single worktree (or none) — flat session list.
  flat,

  /// Multiple worktrees — grouped collapsible sections.
  grouped,
}

/// Snapshot of [WorktreeState] fields that drive [WorkspaceSidebar] grouping.
class WorktreeSidebarView {
  const WorktreeSidebarView({
    required this.worktrees,
    required this.collapsed,
    required this.currentWorktreePath,
    required this.loading,
  });

  factory WorktreeSidebarView.from(WorktreeState state) => WorktreeSidebarView(
        worktrees: state.worktrees,
        collapsed: state.collapsed,
        currentWorktreePath: state.currentWorktreePath,
        loading: state.loading,
      );

  final List<GitWorktree> worktrees;
  final Set<String> collapsed;
  final String currentWorktreePath;
  final bool loading;

  bool get hasMultipleWorktrees => worktrees.length > 1;

  WorktreeSessionListLayout get sessionListLayout {
    if (worktrees.length > 1) return WorktreeSessionListLayout.grouped;
    if (loading && worktrees.isEmpty) {
      return WorktreeSessionListLayout.indeterminate;
    }
    return WorktreeSessionListLayout.flat;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorktreeSidebarView &&
          sessionListLayout == other.sessionListLayout &&
          currentWorktreePath == other.currentWorktreePath &&
          _setEquals(collapsed, other.collapsed) &&
          _worktreePathsEqual(worktrees, other.worktrees);

  @override
  int get hashCode => Object.hash(
        sessionListLayout,
        currentWorktreePath,
        _collapsedHash(collapsed),
        Object.hashAll(worktrees.map((w) => w.path)),
      );

  static int _collapsedHash(Set<String> collapsed) {
    final sorted = collapsed.toList()..sort();
    return Object.hashAll(sorted);
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _worktreePathsEqual(List<GitWorktree> a, List<GitWorktree> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path) return false;
    }
    return true;
  }
}

class WorktreeCubit extends Cubit<WorktreeState> {
  WorktreeCubit({
    WorktreeLister? lister,
    this.workspaceId = '',
    WorktreeUiPrefsStore? prefsStore,
    WorkspaceWorktreeStore? worktreeStore,
    String? initialRepoPath,
  })  : _lister = lister,
        _prefsStore = prefsStore ?? WorktreeUiPrefsStore(),
        _worktreeStore = worktreeStore,
        super(
          _initialState(
            workspaceId: workspaceId,
            worktreeStore: worktreeStore,
            initialRepoPath: initialRepoPath,
          ),
        );

  WorktreeLister? _lister;
  final WorktreeUiPrefsStore _prefsStore;
  final WorkspaceWorktreeStore? _worktreeStore;

  /// Scopes persisted UI state (collapse + current worktree). Empty disables
  /// persistence (e.g. in unit tests that don't exercise it).
  final String workspaceId;

  bool _hydrated = false;

  static WorktreeState _initialState({
    required String workspaceId,
    required WorkspaceWorktreeStore? worktreeStore,
    required String? initialRepoPath,
  }) {
    final repo = initialRepoPath?.trim() ?? '';
    if (repo.isEmpty) return const WorktreeState();

    final cached = workspaceId.trim().isNotEmpty
        ? worktreeStore?.peek(workspaceId, repo)
        : null;
    if (cached != null && cached.worktrees.isNotEmpty) {
      return WorktreeState(
        repoPath: repo,
        worktrees: cached.worktrees,
        currentWorktreePath: cached.worktrees.first.path,
        loading: true,
      );
    }
    // No cached worktrees yet, but a load() is coming (bindWorktreeService runs
    // on first tools-scope sync). Start in the indeterminate (loading) state so
    // the sidebar paints the skeleton, not the full flat session list that it
    // would then immediately throw away once the worktree list resolves.
    return WorktreeState(
      repoPath: repo,
      currentWorktreePath: repo,
      loading: true,
    );
  }

  /// Binds the git runner for the resolved workspace tools plane and loads the
  /// worktree list. Called when the workspace tools [targetId] changes;
  /// per-session worktree selection uses [syncCurrentForSessionPath].
  void bindWorktreeService(
    GitWorktreeService service, {
    required String repoPath,
    String? preferCurrentPath,
  }) {
    _lister = _GitWorktreeLister(service);
    unawaited(load(repoPath, preferCurrentPath: preferCurrentPath));
  }

  /// Loads the worktree list. Selection priority: an existing valid in-memory
  /// selection (across reload) → the persisted last current worktree → the one
  /// containing [preferCurrentPath] (e.g. the active session's directory, §7) →
  /// the main worktree. Collapse state is hydrated from disk on first load.
  Future<void> load(String repoPath, {String? preferCurrentPath}) async {
    final lister = _lister;
    if (lister == null) {
      throw StateError(
        'WorktreeCubit.load before bindWorktreeService (or test lister)',
      );
    }

    emit(state.copyWith(repoPath: repoPath, loading: true));

    final hydrating = !_hydrated && workspaceId.isNotEmpty;
    final listFuture = lister.list(repoPath);
    final prefFuture =
        hydrating ? _prefsStore.prefsFor(workspaceId) : Future<WorktreeUiPref?>.value(null);

    final list = await listFuture;
    final pref = await prefFuture;
    if (isClosed) return;
    if (hydrating) _hydrated = true;

    var collapsed = state.collapsed;
    String? persistedCurrent;
    if (pref != null) {
      collapsed = pref.collapsed;
      persistedCurrent = pref.currentPath;
    }

    bool inList(String path) =>
        path.isNotEmpty && list.any((w) => workspacePathsEqual(w.path, path));

    final String current;
    if (inList(state.currentWorktreePath)) {
      current = state.currentWorktreePath;
    } else if (persistedCurrent != null && inList(persistedCurrent)) {
      current = persistedCurrent;
    } else {
      current = _initialCurrent(list, preferCurrentPath, repoPath);
    }
    emit(state.copyWith(
      worktrees: list,
      currentWorktreePath: current,
      collapsed: collapsed,
      loading: false,
    ));
    if (workspaceId.isNotEmpty) {
      _worktreeStore?.remember(workspaceId, repoPath, list);
    }
  }

  void _persist() {
    if (workspaceId.isEmpty) return;
    unawaited(_prefsStore.save(
      workspaceId,
      WorktreeUiPref(
        collapsed: state.collapsed,
        currentPath: state.currentWorktreePath,
      ),
    ));
  }

  /// Worktree whose path is the longest prefix of [preferPath]; else the main
  /// (first) worktree; else [repoPath] when the list is empty.
  static String _initialCurrent(
    List<GitWorktree> list,
    String? preferPath,
    String repoPath,
  ) {
    if (preferPath != null && preferPath.isNotEmpty) {
      final best = worktreePathForSessionPath(preferPath, list);
      if (best != null) return best;
    }
    return list.isNotEmpty ? list.first.path : repoPath;
  }

  /// Sets [currentWorktreePath] to the worktree that contains [sessionPrimaryPath].
  /// No-op when the list is empty or the session is orphaned.
  void syncCurrentForSessionPath(String sessionPrimaryPath) {
    if (state.worktrees.isEmpty) return;
    final path = worktreePathForSessionPath(sessionPrimaryPath, state.worktrees);
    if (path != null) setCurrentWorktree(path);
  }

  void setCurrentWorktree(String path) {
    emit(state.copyWith(currentWorktreePath: normalizeWorkspacePath(path)));
    _persist();
  }

  void toggleCollapsed(String path) {
    final next = {...state.collapsed};
    next.contains(path) ? next.remove(path) : next.add(path);
    emit(state.copyWith(collapsed: next));
    _persist();
  }
}
