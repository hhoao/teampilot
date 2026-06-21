import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/git_worktree.dart';
import '../services/git/git_worktree_service.dart';
import '../services/home_workspace/worktree_ui_prefs_store.dart';
import '../utils/session_worktree_grouping.dart';
import '../utils/workspace_path_utils.dart';

/// Narrow seam so tests inject a fake without a real GitWorktreeService.
abstract class WorktreeLister {
  Future<List<GitWorktree>> list(String repoPath);
}

class _ServiceLister implements WorktreeLister {
  _ServiceLister(this._svc);
  final GitWorktreeService _svc;
  @override
  Future<List<GitWorktree>> list(String repoPath) => _svc.list(repoPath);
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

class WorktreeCubit extends Cubit<WorktreeState> {
  WorktreeCubit({
    WorktreeLister? lister,
    GitWorktreeService? service,
    this.workspaceId = '',
    WorktreeUiPrefsStore? prefsStore,
  })  : _lister = lister ??
            _ServiceLister(service ??
                GitWorktreeService.debugOverrideFactory?.call() ??
                GitWorktreeService()),
        _prefsStore = prefsStore ?? WorktreeUiPrefsStore(),
        super(const WorktreeState());

  final WorktreeLister _lister;
  final WorktreeUiPrefsStore _prefsStore;

  /// Scopes persisted UI state (collapse + current worktree). Empty disables
  /// persistence (e.g. in unit tests that don't exercise it).
  final String workspaceId;

  bool _hydrated = false;

  /// Loads the worktree list. Selection priority: an existing valid in-memory
  /// selection (across reload) → the persisted last current worktree → the one
  /// containing [preferCurrentPath] (e.g. the active session's directory, §7) →
  /// the main worktree. Collapse state is hydrated from disk on first load.
  Future<void> load(String repoPath, {String? preferCurrentPath}) async {
    emit(state.copyWith(repoPath: repoPath, loading: true));
    final list = await _lister.list(repoPath);

    var collapsed = state.collapsed;
    String? persistedCurrent;
    if (!_hydrated && workspaceId.isNotEmpty) {
      _hydrated = true;
      final pref = await _prefsStore.prefsFor(workspaceId);
      if (pref != null) {
        collapsed = pref.collapsed;
        persistedCurrent = pref.currentPath;
      }
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
